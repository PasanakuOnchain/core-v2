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
_PARTICIPANT_COUNT: constant(uint256) = 12


# @dev Amount of ERC-1155 tokens minted per participant when a round starts (one id per pasanaku).
_TOKEN_MINT_AMOUNT: constant(uint256) = 1


# @dev Offset for `token_id` values.
_TOKEN_ID_OFFSET: constant(uint256) = 1


# @dev Minimum elapsed time in seconds between consecutive `tick` payouts for a round.
_DAYS_30: constant(uint256) = 30 * 24 * 60 * 60


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
# token_id -> tick_index -> participant -> bool
_deposited_for_pasanaku_tick: HashMap[
    uint256, HashMap[uint256, HashMap[address, bool]]
]


@deploy
@payable
def __init__(
    base_uri_: String[80], supported_assets: address[_SUPPORTED_ASSETS_COUNT]
):
    """
    @dev To omit the opcodes for checking `msg.value` in creation bytecode, the constructor
         is `payable`. Initialises `ownable` (owner is `msg.sender`), initialises `erc1155`
         with `base_uri_`, and stores `supported_assets` in `_SUPPORTED_ASSETS`.
    @param base_uri_ The maximum 80-character base URI passed to the `erc1155` module.
    @param supported_assets The allowlisted collateral token addresses for this deployment.
    """
    ow.__init__()
    erc1155.__init__(base_uri_)
    _SUPPORTED_ASSETS = supported_assets
    self._counter = _TOKEN_ID_OFFSET


@external
@nonreentrant
def deposit(asset: address, amount: uint256, token_id: uint256):
    """
    @dev If `token_id == empty(uint256)` or `< _TOKEN_ID_OFFSET`, credits `_collateral` for
         `(msg.sender, asset)`; otherwise asserts `token_id < self._counter` and invokes
         `_deposit_for_token` for the current payout index. Calls `transferFrom` from `msg.sender`.
         Emits `CollateralDeposited`.
    @param asset Supported ERC-20 collateral.
    @param amount Tokens to pull (> 0).
    @param token_id Allocation id for pooled balance vs tick pledge modes (see code branch).
    """
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset
    assert amount > 0  # dev: invalid amount

    if token_id == empty(uint256) or token_id < _TOKEN_ID_OFFSET:
        self._collateral[msg.sender][asset] += amount
    else:
        assert token_id < self._counter  # dev: invalid token id
        self._deposit_for_token(msg.sender, amount, token_id)

    extcall IERC20(asset).transferFrom(msg.sender, self, amount)

    log IPasanaku.CollateralDeposited(
        account=msg.sender,
        asset=asset,
        amount=amount,
        balance_after=self._collateral[msg.sender][asset],
    )


@external
@nonreentrant
def withdraw(asset: address, amount: uint256):
    """
    @dev Decrements withdrawable collateral and sends `amount` to `msg.sender`. Requires
         `_collateral` minus `_collateral_in_use`. Emits `CollateralWithdrawn`.
    @param asset The ERC-20 token to withdraw.
    @param amount The amount to send; must not exceed withdrawable balance.
    """
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset
    assert amount > 0  # dev: invalid amount

    collateral: uint256 = self._collateral[msg.sender][asset]
    collateral_in_use: uint256 = self._collateral_in_use[msg.sender][asset]
    assert collateral > collateral_in_use  # dev: collateral in use
    assert (
        collateral - collateral_in_use >= amount
    )  # dev: insufficient collateral

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
    assert (
        collateral - in_use >= pasanaku_amount
    )  # dev: collateral already pledged

    pasanaku.participants.append(msg.sender)
    self._pasanakus[token_id] = pasanaku
    self._collateral_in_use[msg.sender][pasanaku.asset] += pasanaku_amount

    if len(pasanaku.participants) == _PARTICIPANT_COUNT:
        self._start_pasanaku(token_id)

    log IPasanaku.PasanakuJoined(
        token_id=token_id,
        account=msg.sender,
        participant_count=len(pasanaku.participants),
    )


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
    extcall IERC20(pasanaku.asset).transfer(participant, pasanaku.amount)

    # Update pasanaku in storage
    self._pasanakus[token_id] = pasanaku


@external
def recover(asset: address, amount: uint256):
    """
    @dev Owner-only rescue for tokens that are not in `_SUPPORTED_ASSETS`. Transfers `amount` to
         `msg.sender`. Emits `Recovered`.
    @notice Does not use accounting mappings; caller must ensure the balance exists.
    @param asset Must not be a supported collateral asset.
    @param amount The amount to transfer out.
    """
    ow._check_owner()
    assert asset not in _SUPPORTED_ASSETS  # dev: cannot be a supported asset
    extcall IERC20(asset).transfer(msg.sender, amount)
    log IPasanaku.Recovered(
        account=msg.sender,
        asset=asset,
        amount=amount,
    )


@external
def safeTransferFrom(
    owner: address, to: address, id: uint256, amount: uint256, data: Bytes[1024]
):
    """
    @notice Pasanaku ERC-1155 tokens are non-transferable (soulbound).
    @dev Always reverts with `pasanaku: pasanakus are soul-bounded tokens`.
    @param owner Unused; included for IERC1155 compatibility.
    @param to Unused; included for IERC1155 compatibility.
    @param id Unused; included for IERC1155 compatibility.
    @param amount Unused; included for IERC1155 compatibility.
    @param data Unused; included for IERC1155 compatibility.
    """
    raise "pasanaku: pasanakus are soul-bounded tokens"


@external
def safeBatchTransferFrom(
    owner: address,
    to: address,
    ids: DynArray[uint256, 128],
    amounts: DynArray[uint256, 128],
    data: Bytes[1024],
):
    """
    @notice Pasanaku ERC-1155 tokens are non-transferable (soulbound).
    @dev Always reverts with `pasanaku: pasanakus are soul-bounded tokens`.
    @param owner Unused; included for IERC1155 compatibility.
    @param to Unused; included for IERC1155 compatibility.
    @param ids Unused; included for IERC1155 compatibility.
    @param amounts Unused; included for IERC1155 compatibility.
    @param data Unused; included for IERC1155 compatibility.
    """
    raise "pasanaku: pasanakus are soul-bounded tokens"


@external
def setApprovalForAll(operator: address, approved: bool):
    """
    @notice Pasanaku ERC-1155 tokens are non-transferable (soulbound); operators are not used.
    @dev Always reverts with `pasanaku: pasanakus are soul-bounded tokens`.
    @param operator Unused; included for IERC1155 compatibility.
    @param approved Unused; included for IERC1155 compatibility.
    """
    raise "pasanaku: pasanakus are soul-bounded tokens"


@external
@view
def uri(id: uint256) -> String[512]:
    """
    @dev Returns a lifecycle-specific metadata URI for `id` based on `_pasanakus[id]` timestamps.
    @param id Round key / ERC-1155 id in `_pasanakus` (pending phase still returns URLs).
    @return String[512] Pending, started, or ended URL string.
    """
    pasanaku: IPasanaku.Pasanaku = self._pasanakus[id]
    if pasanaku.ended != empty(uint256):
        return "https://pasanaku.fun/pasanaku/ended"

    if pasanaku.started != empty(uint256):
        return "https://pasanaku.fun/pasanaku/started"

    return "https://pasanaku.fun/pasanaku/pending"


@external
@view
def isApprovedForAll(arg0: address, arg1: address) -> bool:
    """
    @dev Soulbound token configuration: approvals are disabled.
    @param arg0 The owner address (unused).
    @param arg1 The operator address (unused).
    @return bool Always `False`.
    """
    return False


@external
@view
def pasanaku(pasanaku_id: uint256) -> IPasanaku.Pasanaku:
    """
    @dev Returns `_pasanakus[pasanaku_id]` (pending cohort, active round, or ended record).
    @param pasanaku_id Counter `token_id` used as round key (`create_pasanaku` / ERC-1155 id).
    @return Pasanaku The stored `IPasanaku.Pasanaku` struct.
    """
    return self._pasanakus[pasanaku_id]


@external
@view
def collateral_in_use(participant: address, asset: address) -> uint256:
    """
    @dev Amount of `_collateral[participant][asset]` reserved by `join_pasanaku`; not usable for
         `withdraw` until the round completes and pledge is freed.
    @param participant The account to query.
    @param asset The ERC-20 token address.
    @return uint256 Value in `_collateral_in_use[participant][asset]`.
    """
    return self._collateral_in_use[participant][asset]


@external
@view
def deposited_for_pasanaku(
    pasanaku_id: uint256, tick_index: uint256, participant: address
) -> bool:
    """
    @dev Whether `participant` deposited for the payout index `tick_index` on pasanaku
         `pasanaku_id`.
    @param pasanaku_id Round `token_id`.
    @param tick_index Tick deposit slot keyed in `_deposited_for_pasanaku_tick`.
    @param participant The account to query.
    @return bool Value from `_deposited_for_pasanaku_tick`.
    """
    return self._deposited_for_pasanaku_tick[pasanaku_id][tick_index][
        participant
    ]


@external
@view
def participant_count() -> uint256:
    """
    @dev Fixed cohort size for each pasanaku round.
    @return uint256 `_PARTICIPANT_COUNT` (12).
    """
    return _PARTICIPANT_COUNT


@view
@external
def supported_assets() -> address[_SUPPORTED_ASSETS_COUNT]:
    """
    @dev Collateral allowlist configured at deployment.
    @return address[_SUPPORTED_ASSETS_COUNT] The immutable `_SUPPORTED_ASSETS` array.
    """
    return _SUPPORTED_ASSETS


@view
@external
def collateral(participant: address, asset: address) -> uint256:
    """
    @dev Participant balance of supported `asset` held by the protocol (`deposit`/`withdraw`).
    @param participant The account to query.
    @param asset The ERC-20 token address.
    @return uint256 `_collateral[participant][asset]`.
    """
    return self._collateral[participant][asset]


@internal
def _deposit_for_token(
    participant: address,
    amount: uint256,
    token_id: uint256,
):
    """
    @dev Records tick collateral: sets `_deposited_for_pasanaku_tick[token_id][tick_index][participant]`
         for `tick_index == pasanaku.active_participant` when `amount >= pasanaku.amount`.
         Emits `TickDepositMarked`.
    @param participant The depositor (`msg.sender` in `deposit`); must be in the cohort.
    @param amount The tokens pulled in outer `deposit` (minimum `pasanaku.amount`).
    @param token_id Active pasanaku counter id (`token_id`).
    """
    pasanaku: IPasanaku.Pasanaku = self._pasanakus[token_id]
    tick_index: uint256 = pasanaku.active_participant

    assert pasanaku.started != empty(uint256)  # dev: pasanaku not started
    assert pasanaku.ended == empty(uint256)  # dev: pasanaku ended
    assert participant in pasanaku.participants  # dev: participant not in pasanaku # nosplit
    assert not self._deposited_for_pasanaku_tick[token_id][tick_index][participant]  # dev: already deposited # nosplit
    assert amount >= pasanaku.amount  # dev: insufficient amount

    self._deposited_for_pasanaku_tick[token_id][tick_index][participant] = True

    log IPasanaku.TickDepositMarked(
        participant=participant,
        token_id=token_id,
        tick_index=tick_index,
        asset=pasanaku.asset,
        amount=amount,
    )


@internal
def _start_pasanaku(token_id: uint256):
    """
    @dev When the cohort is full: sets struct `token_id`, `started`, `updated` on `_pasanakus[token_id]`,
         mints `_TOKEN_MINT_AMOUNT` ERC-1155 per participant at id `token_id`. Emits
         `PasanakuStarted`.
    @param token_id The cohort key from `create_pasanaku`; same ERC-1155 id after mint.
    """
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

