# pragma version ==0.4.3
# pragma nonreentrancy off
"""
@title `Pasanaku` - Pasanaku contract
@custom:contract-name Pasanaku
@license GNU Affero General Public License v3.0 only
@author Rafael Abuawad <x.com/rabuawad_>
@notice Pasanaku: collateral-held rotating payouts using Snekmate `erc1155` with metadata URI
        (`uri`) and ERC-165; ownership uses Snekmate `ownable`. Filled cohorts share one ERC-1155 id
        (soulbound: transfer and approve entrypoints revert on this deployment). Exported read/write
        from `erc1155` includes `owner`, `supportsInterface`, `balanceOfBatch`, `exists`, `balanceOf`,
        `total_supply`. Round `@external` and `@view` entrypoints appear below per `implements IPasanaku`.
@dev Composes Snekmate modules with round state and events from `IPasanaku`; single canonical round
      key `token_id` minted once the cohort is complete.
"""

# @dev We import the `IERC20` interface.
from ethereum.ercs import IERC20


# @dev We import and implement the `IERC165` interface.
from ethereum.ercs import IERC165
implements: IERC165


# @dev We import and implement the `IERC1155` interface.
from snekmate.tokens.interfaces import IERC1155
implements: IERC1155


# @dev We import and implement the `IERC1155MetadataURI`.
from snekmate.tokens.interfaces import IERC1155MetadataURI
implements: IERC1155MetadataURI


# @dev We import and initialise the `ownable` module.
from snekmate.auth import ownable as ow
initializes: ow


# @dev We import and implement the `IPasanaku` interface.
from interfaces import IPasanaku
implements: IPasanaku


# @dev We import and initialise the `erc1155` module.
from snekmate.tokens import erc1155
initializes: erc1155[ownable := ow]
exports: (
    erc1155.owner,
    erc1155.supportsInterface,
    erc1155.balanceOfBatch,
    erc1155.exists,
    erc1155.balanceOf,
    erc1155.total_supply,
)


# @dev Maximum participants per pasanaku round (fixed cohort size).
_PARTICIPANT_COUNT: constant(uint256) = 10


# @dev Amount of ERC-1155 tokens minted per participant when a round starts (one id per pasanaku).
_TOKEN_MINT_AMOUNT: constant(uint256) = 1


# @dev Offset for `token_id` values.
_TOKEN_ID_OFFSET: constant(uint256) = 1


# @dev Minimum elapsed time in seconds between consecutive `tick` payouts for a round.
_DAYS_30: constant(uint256) = 30 * 24 * 60 * 60

# Wait time
_DAYS_10: constant(uint256) = 10 * 24 * 60 * 60

# @dev Length of the immutable supported-asset allowlist configured at deployment.
_SUPPORTED_ASSETS_COUNT: constant(uint256) = 3


# @dev Allowlisted ERC-20 collateral assets used by collateral flows (`create_pasanaku`, `deposit`,
#      `join_pasanaku`, `withdraw`) and negative allowlist guard in `recover`.
_SUPPORTED_ASSETS: immutable(address[_SUPPORTED_ASSETS_COUNT])


# @dev Counter assigning `token_id` values.
_counter: uint256


# @dev Pasanaku round structs keyed by allocation counter `token_id` (pending cohort or active).
_pasanakus: HashMap[uint256, IPasanaku.Pasanaku]


# @dev Collateral balance per `participant` per `asset`.
_collateral: HashMap[address, HashMap[address, uint256]]


# @dev Portion of `_collateral` reserved because the `participant`
#      has joined pending or active pasanakus.
_collateral_in_use: HashMap[address, HashMap[address, uint256]]


# @dev Whether `participant` has marked collateral for the given
#      `token_id` and `tick_index`.
# @notice Written when `deposit` satisfies tick rules and `_deposit_for_token` runs.
# token_id -> tick_index -> participant -> deposited (bool)
_deposited_for_tick: HashMap[uint256, HashMap[uint256, HashMap[address, bool]]] # nosplit


@deploy
@payable
def __init__(
    base_uri_: String[80], supported_assets: address[_SUPPORTED_ASSETS_COUNT]
):
    ow.__init__()
    erc1155.__init__(base_uri_)
    _SUPPORTED_ASSETS = supported_assets
    self._counter = _TOKEN_ID_OFFSET


@external
@nonreentrant
def add_collateral(asset: address, amount: uint256, token_id: uint256):
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset
    assert amount > 0  # dev: invalid amount

    self._collateral[msg.sender][asset] += amount
    log IPasanaku.CollateralAdded(
        account=msg.sender,
        asset=asset,
        amount=amount,
        balance_after=self._collateral[msg.sender][asset],
    )
    extcall IERC20(asset).transferFrom(msg.sender, self, amount)


@external
@nonreentrant
def deposit_pasanaku(asset: address, amount: uint256, token_id: uint256):
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset
    assert amount > 0  # dev: invalid amount
    assert token_id >= _TOKEN_ID_OFFSET  # dev: invalid token id

    pasanaku: IPasanaku.Pasanaku = self._pasanakus[token_id]
    tick_index: uint256 = pasanaku.active_participant

    assert pasanaku.started != empty(uint256)  # dev: pasanaku not started
    assert pasanaku.ended == empty(uint256)  # dev: pasanaku ended
    assert msg.sender in pasanaku.participants  # dev: participant not in pasanaku # nosplit
    assert erc1155.balanceOf[msg.sender][token_id] != 0  # dev: not a participant
    assert not self._deposited_for_tick[token_id][tick_index][msg.sender]  # dev: already deposited # nosplit
    assert amount >= pasanaku.amount  # dev: insufficient amount
    assert block.timestamp - pasanaku.updated < _DAYS_10  # dev: not enough time passed # nosplit

    self._deposited_for_tick[token_id][tick_index][msg.sender] = True

    log IPasanaku.TickDepositMarked(
        participant=msg.sender,
        token_id=token_id,
        tick_index=tick_index,
        asset=pasanaku.asset,
        amount=amount,
    )
    extcall IERC20(asset).transferFrom(msg.sender, self, amount)


@external
@nonreentrant
def withdraw(asset: address, amount: uint256):
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset
    assert amount > 0  # dev: invalid amount

    collateral: uint256 = self._collateral[msg.sender][asset]
    collateral_in_use: uint256 = self._collateral_in_use[msg.sender][asset]
    assert collateral > collateral_in_use  # dev: collateral in use
    assert collateral - collateral_in_use >= amount  # dev: insufficient collateral 

    self._collateral[msg.sender][asset] -= amount
    extcall IERC20(asset).transfer(msg.sender, amount)

    log IPasanaku.CollateralWithdrawn(
        account=msg.sender,
        asset=asset,
        amount=amount,
        balance_after=self._collateral[msg.sender][asset],
    )


@external
def create_pasanaku(asset: address, amount: uint256) -> uint256:
    """
    @dev Appends a pending pasanaku with empty participants and returns its `pending_index`
         (the value of `_counter` before increment). Emits `PasanakuCreated`.
    @param asset Supported collateral token; must be in `_SUPPORTED_ASSETS`.
    @param amount Per-tick payout amount for the round.
    @return uint256 The pending index for `join_pasanaku`.
    """
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset

    token_id: uint256 = self._counter
    self._counter += 1

    pasanaku: IPasanaku.Pasanaku = IPasanaku.Pasanaku(
        token_id=empty(uint256),
        asset=asset,
        amount=amount,
        participants=empty(DynArray[address, _PARTICIPANT_COUNT]),
        active_participant=empty(uint256),
        started=empty(uint256),
        updated=empty(uint256),
        ended=empty(uint256),
    )
    self._pasanakus[token_id] = pasanaku

    log IPasanaku.PasanakuCreated(
        token_id=token_id,
        asset=asset,
        amount=amount,
    )
    return token_id


@external
@nonreentrant
def join_pasanaku(token_id: uint256):
    """
    @dev Appends `msg.sender` as participant; increments `_collateral_in_use` by
         `pasanaku.amount * _PARTICIPANT_COUNT`. Calls `_start_pasanaku` when the cohort fills.
         Emits `PasanakuJoined`.
    @notice Free collateral `_collateral` minus `_collateral_in_use` for `pasanaku.asset` must cover
           the pledge above before join.
    @param token_id `create_pasanaku` return; must satisfy `token_id < self._counter`.
    """

    assert token_id < self._counter  # dev: invalid token id

    pasanaku: IPasanaku.Pasanaku = self._pasanakus[token_id]
    assert msg.sender not in pasanaku.participants  # dev: participant already joined # nosplit

    pasanaku_amount: uint256 = pasanaku.amount * _PARTICIPANT_COUNT
    assert self._collateral[msg.sender][pasanaku.asset] >= pasanaku_amount  # dev: insufficient collateral # nosplit

    collateral: uint256 = self._collateral[msg.sender][pasanaku.asset]
    in_use: uint256 = self._collateral_in_use[msg.sender][pasanaku.asset]
    assert collateral - in_use >= pasanaku_amount  # dev: collateral already pledged # nosplit

    pasanaku.participants.append(msg.sender)
    self._pasanakus[token_id] = pasanaku
    self._collateral_in_use[msg.sender][pasanaku.asset] += pasanaku_amount

    log IPasanaku.PasanakuJoined(
        token_id=token_id,
        account=msg.sender,
        participant_count=len(pasanaku.participants),
    )

    if len(pasanaku.participants) == _PARTICIPANT_COUNT:
        self._start_pasanaku(token_id)


@external
@nonreentrant
def tick(token_id: uint256):
    """
    @dev Uses `tick_index := pasanaku.active_participant` (then increments `active_participant`);
         transfers `pasanaku.amount` of `pasanaku.asset` to the chosen participant, updates timestamps, emits `PasanakuTicked`
         until the last index emits `PasanakuEnded` and calls `_unlock_collateral_in_use`.
    @notice Requires `_DAYS_30` elapsed since `pasanaku.updated` (last payout or round start).
    @param token_id The ERC-1155 token id (`token_id`) for the active round.
    """
    pasanaku: IPasanaku.Pasanaku = self._pasanakus[token_id]
    assert pasanaku.started != empty(uint256)  # dev: pasanaku not started
    assert pasanaku.ended == empty(uint256)  # dev: pasanaku ended
    assert pasanaku.updated + _DAYS_30 <= block.timestamp  # dev: not enough time passed # nosplit
    assert block.timestamp - pasanaku.updated >= _DAYS_10  # dev: not enough time passed # nosplit

    index: uint256 = pasanaku.active_participant
    pasanaku.active_participant += 1

    participant: address = pasanaku.participants[index]
    pasanaku.updated = block.timestamp

    if index == _PARTICIPANT_COUNT - 1:
        pasanaku.ended = block.timestamp
        self._unlock_collateral_in_use(token_id, pasanaku)
        log IPasanaku.PasanakuEnded(
            token_id=token_id,
            asset=pasanaku.asset,
            amount=pasanaku.amount,
            ended_at=block.timestamp,
        )
    else:
        log IPasanaku.PasanakuTicked(
            token_id=token_id,
            tick_index=index,
            recipient=participant,
            asset=pasanaku.asset,
            amount=pasanaku.amount,
            updated_at=block.timestamp,
        )

    # Transfer collateral to participant
    amount: uint256 = self._move_deposit_or_collateral(token_id)
    extcall IERC20(pasanaku.asset).transfer(participant, amount)

    # Update pasanaku in storage
    self._pasanakus[token_id] = pasanaku


@external
def safeTransferFrom(
    owner: address, to: address, id: uint256, amount: uint256, data: Bytes[1024]
):
    raise "pasanaku: pasanakus are soul-bounded tokens"


@external
def safeBatchTransferFrom(
    owner: address,
    to: address,
    ids: DynArray[uint256, 128],
    amounts: DynArray[uint256, 128],
    data: Bytes[1024],
):
    raise "pasanaku: pasanakus are soul-bounded tokens"


@external
def setApprovalForAll(operator: address, approved: bool):
    raise "pasanaku: pasanakus are soul-bounded tokens"


@external
@view
def uri(id: uint256) -> String[512]:
    pasanaku: IPasanaku.Pasanaku = self._pasanakus[id]

    if pasanaku.started == empty(uint256):
        return "https://pasanaku.fun/pasanaku/started"

    if pasanaku.ended != empty(uint256):
        return "https://pasanaku.fun/pasanaku/ended"

    if pasanaku.started != empty(uint256):
        return "https://pasanaku.fun/pasanaku/started"

    return "https://pasanaku.fun/pasanaku/pending"


@external
@view
def isApprovedForAll(arg0: address, arg1: address) -> bool:
    return False


@external
@view
def pasanaku(pasanaku_id: uint256) -> IPasanaku.Pasanaku:
    return self._pasanakus[pasanaku_id]


@external
@view
def collateral_in_use(participant: address, asset: address) -> uint256:
    return self._collateral_in_use[participant][asset]


@external
@view
def deposited_for_pasanaku(
    pasanaku_id: uint256, tick_index: uint256, participant: address
) -> bool:
    return self._deposited_for_tick[pasanaku_id][tick_index][
        participant
    ]


@external
@view
def participant_count() -> uint256:
    return _PARTICIPANT_COUNT


@view
@external
def supported_assets() -> address[_SUPPORTED_ASSETS_COUNT]:
    return _SUPPORTED_ASSETS


@view
@external
def collateral(participant: address, asset: address) -> uint256:
    return self._collateral[participant][asset]


@internal
def _start_pasanaku(token_id: uint256):
    pasanaku: IPasanaku.Pasanaku = self._pasanakus[token_id]
    assert pasanaku.asset != empty(address)  # dev: pasanaku not created

    # Update pasanaku
    pasanaku.token_id = token_id
    pasanaku.started = block.timestamp
    pasanaku.updated = block.timestamp

    # Update pasanaku storage
    self._pasanakus[token_id] = pasanaku

    # Mint tokens
    for participant: address in pasanaku.participants:
        erc1155._safe_mint(participant, token_id, _TOKEN_MINT_AMOUNT, b"")

    log IPasanaku.PasanakuStarted(
        token_id=token_id,
        asset=pasanaku.asset,
        amount=pasanaku.amount,
        started_at=block.timestamp,
    )


@internal
def _unlock_collateral_in_use(token_id: uint256, pasanaku: IPasanaku.Pasanaku):
    """
    @dev After the final payout, reduces `_collateral_in_use` for each cohort member by full-round
         pledge (`pasanaku.amount * _PARTICIPANT_COUNT`).
    @param token_id Unused in body; echoed for readability at `tick` call site.
    @param pasanaku Snapshot of the cohort; pledge scaled by `amount * _PARTICIPANT_COUNT` per participant.
    """
    for participant: address in pasanaku.participants:
        self._collateral_in_use[participant][pasanaku.asset] -= (
            pasanaku.amount * _PARTICIPANT_COUNT
        )


@internal
def _move_deposit_or_collateral(token_id: uint256) -> uint256:
    assert token_id >= _TOKEN_ID_OFFSET  # dev: invalid token id

    pasanaku: IPasanaku.Pasanaku = self._pasanakus[token_id]
    index: uint256 = pasanaku.active_participant
    assert pasanaku.started != empty(uint256)  # dev: pasanaku not started

    for p: address in pasanaku.participants:
        if not self._deposited_for_tick[token_id][index][p]:
            self._collateral[p][pasanaku.asset] -= pasanaku.amount
    
    return 0


@internal
@view
def _amount_deposited_for_tick(token_id: uint256, index: uint256) -> uint256:
    pasanaku: IPasanaku.Pasanaku = self._pasanakus[token_id]
    total: uint256 = 0
    for p: address in pasanaku.participants:
        if not self._deposited_for_tick[token_id][index][p]:
            total += pasanaku.amount
    return total
