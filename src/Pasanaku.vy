# pragma version ==0.4.3
# pragma nonreentrancy off
"""
@title `Pasanaku` - Pasanaku contract
@custom:contract-name Pasanaku
@license GNU Affero General Public License v3.0 only
@author Rafael Abuawad <x.com/rabuawad_>
@notice This contract composes snekmate's `erc1155` module (ERC-1155, ERC-1155 metadata URI
        extension, and ERC-165 via `supportsInterface`) with the `IPasanaku` interface for
        collateralised rotating savings rounds. Each started round is represented by an ERC-1155
        token id minted to participants. Tokens are non-transferable (soulbound): the ERC-1155
        transfer and approval entrypoints always revert. Pasanaku-specific `external` and `view`
        functions: `__init__(base_uri_, supported_assets)`, `deposit`, `withdraw`, `create_pasanaku`,
        `join_pasanaku`, `tick`, `skim`, `recover`, `safeTransferFrom`, `safeBatchTransferFrom`,
        `setApprovalForAll`, `uri`, `isApprovedForAll`, `pasanaku`, `pending_pasanaku`, `deposited`,
        `collateral_in_use`, `deposited_for_token`, `participant_count`, `supported_assets`,
        `total_deposited`. Re-exported from `erc1155`: `owner`, `supportsInterface`, `balanceOfBatch`,
        `exists`, `balanceOf`, `total_supply`.
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


# @dev Minimum elapsed time in seconds between consecutive `tick` payouts for a round.
_DAYS_30: constant(uint256) = 30 * 24 * 60 * 60


# @dev Length of the immutable supported-asset allowlist configured at deployment.
_SUPPORTED_ASSETS_COUNT: constant(uint256) = 3


# @dev Allowlisted ERC-20 collateral assets; used by `create_pasanaku`, `skim`, and `recover` rules.
# @notice Fixed-size array set once in the constructor; not iterable on-chain.
_SUPPORTED_ASSETS: immutable(address[_SUPPORTED_ASSETS_COUNT])


# @dev Monotonic counter assigning `pending_index` values; valid pending indices satisfy `index < _counter`.
_counter: uint256


# @dev Pending rounds keyed by `pending_index` until the cohort fills and `_start_pasanaku` runs.
_pending_pasanakus: HashMap[uint256, IPasanaku.Pasanaku]


# @dev Active rounds keyed by ERC-1155 `token_id` after the round has started.
_pasanakus: HashMap[uint256, IPasanaku.Pasanaku]


# @dev For each `token_id`, the index into `participants` for the next `tick` payout.
_active_participant: HashMap[uint256, uint256]


# @dev Credited ERC-20 balance per account per asset (includes amounts counted in `_in_use`).
_deposited: HashMap[address, HashMap[address, uint256]]


# @dev Sum over all participants of `_deposited[participant][asset]`; protocol accounting for `skim`.
_total_deposited: HashMap[address, uint256]


# @dev Portion of `_deposited` reserved because the account has joined pending or active pasanakus.
_in_use: HashMap[address, HashMap[address, uint256]]


# @dev Whether `participant` has marked collateral for the given `pasanaku_id` and `tick_index`.
# @notice Written when `deposit` is called with a non-zero `pasanaku_id` and `_deposit_for_token` succeeds.
_deposited_for_token: HashMap[uint256, HashMap[uint256, HashMap[address, bool]]]


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


@external
@nonreentrant
def deposit(
    asset: address,
    amount: uint256,
    pasanaku_id: uint256,
    tick_index: uint256,
):
    """
    @dev Credits `amount` of `asset` to `msg.sender` in `_deposited` and `_total_deposited`, optionally
         records tick collateral via `_deposit_for_token` when `pasanaku_id` is non-zero, then pulls
         tokens with `transferFrom`. Emits `CollateralDeposited`.
    @notice State is updated before the ERC-20 transfer (checks-effects-interactions).
    @param asset The ERC-20 token pulled from the caller.
    @param amount The amount to deposit; must be positive; if marking a tick deposit, must be
           at least the pasanaku payout amount for that round.
    @param pasanaku_id The active pasanaku `token_id`, or zero to skip `_deposit_for_token`.
    @param tick_index The payout index when `pasanaku_id` is non-zero.
    """
    assert amount > 0  # dev: invalid amount
    self._deposited[msg.sender][asset] += amount
    self._total_deposited[asset] += amount

    if pasanaku_id != empty(uint256):
        self._deposit_for_token(msg.sender, amount, pasanaku_id, tick_index)

    extcall IERC20(asset).transferFrom(msg.sender, self, amount)

    log IPasanaku.CollateralDeposited(
        account=msg.sender,
        asset=asset,
        amount=amount,
        balance_after=self._deposited[msg.sender][asset],
    )


@external
@nonreentrant
def withdraw(asset: address, amount: uint256):
    """
    @dev Decrements withdrawable collateral and sends `amount` to `msg.sender`. Requires free balance
         (`_deposited` minus `_in_use`). Emits `CollateralWithdrawn`.
    @param asset The ERC-20 token to withdraw.
    @param amount The amount to send; must not exceed withdrawable balance.
    """
    assert amount > 0  # dev: invalid amount

    deposited: uint256 = self._deposited[msg.sender][asset]
    in_use: uint256 = self._in_use[msg.sender][asset]
    assert deposited > in_use  # dev: collateral in use
    assert deposited - in_use >= amount  # dev: collateral in use

    self._deposited[msg.sender][asset] -= amount
    self._total_deposited[asset] -= amount
    extcall IERC20(asset).transfer(msg.sender, amount)

    log IPasanaku.CollateralWithdrawn(
        account=msg.sender,
        asset=asset,
        amount=amount,
        balance_after=self._deposited[msg.sender][asset],
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

    index: uint256 = self._counter
    self._counter += 1

    pasanaku: IPasanaku.Pasanaku = IPasanaku.Pasanaku(
        token_id=empty(uint256),
        asset=asset,
        amount=amount,
        participants=empty(DynArray[address, _PARTICIPANT_COUNT]),
        started=empty(uint256),
        updated=empty(uint256),
        ended=empty(uint256),
    )
    self._pending_pasanakus[index] = pasanaku

    log IPasanaku.PasanakuCreated(
        pending_index=index,
        asset=asset,
        amount=amount,
    )
    return index


@external
@nonreentrant
def join_pasanaku(index: uint256):
    """
    @dev Registers `msg.sender` on a pending pasanaku, locking `amount * _PARTICIPANT_COUNT` of the
         pasanaku asset into `_in_use`. When the cohort is full, calls `_start_pasanaku`.
         Emits `PasanakuJoined`; if the round starts in the same call, also emits `PasanakuStarted`.
    @param index The `pending_index` returned by `create_pasanaku`.
    """
    assert index < self._counter  # dev: invalid index

    pasanaku: IPasanaku.Pasanaku = self._pending_pasanakus[index]
    assert msg.sender not in pasanaku.participants  # dev: participant already joined # nosplit

    pasanake_amount: uint256 = pasanaku.amount * _PARTICIPANT_COUNT
    assert self._deposited[msg.sender][pasanaku.asset] >= pasanake_amount  # dev: insufficient collateral # nosplit

    pasanaku.participants.append(msg.sender)
    self._pending_pasanakus[index] = pasanaku
    self._in_use[msg.sender][pasanaku.asset] += pasanake_amount  # nosplit

    if len(pasanaku.participants) == _PARTICIPANT_COUNT:
        self._start_pasanaku(index)

    log IPasanaku.PasanakuJoined(
        account=msg.sender,
        pending_index=index,
        participant_count=len(pasanaku.participants),
    )


@external
@nonreentrant
def tick(token_id: uint256):
    """
    @dev Pays one participant per call: transfers `pasanaku.amount` of `pasanaku.asset` to the member
         at `_active_participant[token_id]`, advances that index, updates `updated`, and sets `ended`
         on the final tick. Emits `PasanakuTicked`.
    @notice Requires at least `_DAYS_30` seconds since `updated` (or since round start when `updated` is zero).
    @param token_id The ERC-1155 id / pasanaku id for the active round.
    """
    pasanaku: IPasanaku.Pasanaku = self._pasanakus[token_id]
    assert pasanaku.started != empty(uint256)  # dev: pasanaku not started
    assert pasanaku.ended == empty(uint256)  # dev: pasanaku ended
    assert pasanaku.updated + _DAYS_30 <= block.timestamp  # dev: not enough time passed # nosplit

    index: uint256 = self._active_participant[token_id]
    self._active_participant[token_id] += 1

    participant: address = pasanaku.participants[index]
    extcall IERC20(pasanaku.asset).transfer(participant, pasanaku.amount)

    if index == _PARTICIPANT_COUNT - 1:
        pasanaku.ended = block.timestamp

    pasanaku.updated = block.timestamp
    self._pasanakus[token_id] = pasanaku

    log IPasanaku.PasanakuTicked(
        token_id=token_id,
        tick_index=index,
        recipient=participant,
        asset=pasanaku.asset,
        amount=pasanaku.amount,
        updated_at=block.timestamp,
        ended=index == _PARTICIPANT_COUNT - 1,
    )


@external
def skim(asset: address):
    """
    @dev Owner-only. Transfers ERC-20 surplus `balanceOf(this) - _total_deposited[asset]` to `msg.sender`.
         Emits `Skimmed`.
    @notice Only supported assets; reverts if there is no surplus.
    @param asset Must be in `_SUPPORTED_ASSETS`.
    """
    ow._check_owner()
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset

    total_deposited: uint256 = self._total_deposited[asset]
    balance: uint256 = staticcall IERC20(asset).balanceOf(self)
    assert balance > total_deposited  # dev: insufficient extra balance
    extra_balance: uint256 = balance - total_deposited
    extcall IERC20(asset).transfer(msg.sender, extra_balance)
    log IPasanaku.Skimmed(
        account=msg.sender,
        asset=asset,
        amount=extra_balance,
    )


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


@view
@external
def uri(id: uint256) -> String[512]:
    """
    @dev Returns a lifecycle-specific metadata URI for `id` based on `_pasanakus[id]` timestamps.
    @param id The ERC-1155 token id (active pasanaku id).
    @return String[512] Pending, started, or ended URL string.
    """
    pasanaku: IPasanaku.Pasanaku = self._pasanakus[id]
    if pasanaku.ended != empty(uint256):
        return "https://pasanaku.fun/pasanaku/ended"

    if pasanaku.started != empty(uint256):
        return "https://pasanaku.fun/pasanaku/started"

    return "https://pasanaku.fun/pasanaku/pending"


@view
@external
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
    @dev Returns stored round data for a started pasanaku `token_id`.
    @param pasanaku_id The ERC-1155 id / pasanaku id.
    @return Pasanaku The `IPasanaku.Pasanaku` struct from `_pasanakus`.
    """
    return self._pasanakus[pasanaku_id]


@external
@view
def pending_pasanaku(index: uint256) -> IPasanaku.Pasanaku:
    """
    @dev Returns the pending struct at `index` (may be empty after the round has started).
    @param index The `pending_index` from `create_pasanaku`.
    @return Pasanaku The pending or cleared `IPasanaku.Pasanaku` struct.
    """
    return self._pending_pasanakus[index]


@external
@view
def deposited(participant: address, asset: address) -> uint256:
    """
    @dev Credited collateral balance for `participant` in `asset`.
    @param participant The account to query.
    @param asset The ERC-20 token address.
    @return uint256 Amount recorded in `_deposited`.
    """
    return self._deposited[participant][asset]


@external
@view
def collateral_in_use(participant: address, asset: address) -> uint256:
    """
    @dev Collateral from `deposited` reserved for joined pasanakus.
    @param participant The account to query.
    @param asset The ERC-20 token address.
    @return uint256 Amount in `_in_use`.
    """
    return self._in_use[participant][asset]


@external
@view
def deposited_for_token(
    pasanaku_id: uint256, tick_index: uint256, participant: address
) -> bool:
    """
    @dev Whether `participant` completed the tick deposit obligation for the given ids.
    @param pasanaku_id The active pasanaku `token_id`.
    @param tick_index The payout index.
    @param participant The account to query.
    @return bool Value from `_deposited_for_token`.
    """
    return self._deposited_for_token[pasanaku_id][tick_index][participant]


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
def total_deposited(asset: address) -> uint256:
    """
    @dev Protocol-wide sum of credited deposits for `asset` (used for skim accounting).
    @param asset The ERC-20 token address.
    @return uint256 Total in `_total_deposited`.
    """
    return self._total_deposited[asset]


@internal
def _deposit_for_token(
    participant: address,
    amount: uint256,
    pasanaku_id: uint256,
    tick_index: uint256,
):
    """
    @dev Marks `_deposited_for_token` when `participant` deposits at least `pasanaku.amount` for an
         active round and tick. Emits `TickDepositMarked`.
    @param participant The depositor (must be a participant in the round).
    @param amount The deposit amount credited in the outer `deposit` call.
    @param pasanaku_id The active pasanaku `token_id`.
    @param tick_index The payout index being collateralised.
    """
    pasanaku: IPasanaku.Pasanaku = self._pasanakus[pasanaku_id]
    assert pasanaku.started != empty(uint256)  # dev: pasanaku not started
    assert pasanaku.ended == empty(uint256)  # dev: pasanaku ended
    assert participant in pasanaku.participants  # dev: participant not in pasanaku # nosplit
    assert not self._deposited_for_token[pasanaku_id][tick_index][participant]  # dev: already deposited # nosplit
    assert amount >= pasanaku.amount  # dev: insufficient amount

    self._deposited_for_token[pasanaku_id][tick_index][participant] = True

    log IPasanaku.TickDepositMarked(
        participant=participant,
        pasanaku_id=pasanaku_id,
        tick_index=tick_index,
        asset=pasanaku.asset,
        amount=amount,
    )


@internal
def _start_pasanaku(index: uint256):
    """
    @dev Finalises a full pending cohort: assigns `token_id`, moves storage from pending to active,
         mints ERC-1155 tokens, clears the pending slot. Emits `PasanakuStarted`.
    @param index The `pending_index` to start.
    """
    pasanaku: IPasanaku.Pasanaku = self._pending_pasanakus[index]
    assert pasanaku.asset != empty(address)  # dev: pasanaku not created

    # Generate pasanaku id
    pasanaku_id: uint256 = self._generate_pasanaku_id(
        pasanaku.asset, pasanaku.amount, pasanaku.participants
    )

    # Update pasanaku
    pasanaku.token_id = pasanaku_id
    pasanaku.started = block.timestamp

    # Update pasanaku storage
    self._pasanakus[pasanaku_id] = pasanaku
    self._pending_pasanakus[index] = empty(IPasanaku.Pasanaku)

    # Mint tokens
    for participant: address in pasanaku.participants:
        erc1155._safe_mint(participant, pasanaku_id, _TOKEN_MINT_AMOUNT, b"")

    log IPasanaku.PasanakuStarted(
        token_id=pasanaku_id,
        pending_index=index,
        asset=pasanaku.asset,
        amount=pasanaku.amount,
        started_at=block.timestamp,
    )


@internal
@view
def _generate_pasanaku_id(
    asset: address,
    amount: uint256,
    participants: DynArray[address, _PARTICIPANT_COUNT],
) -> uint256:
    """
    @dev Opaque but deterministic id from `keccak256(abi_encode(asset, amount, participants, block.prevhash))`
         cast to `uint256`.
    @param asset The round collateral token.
    @param amount The per-tick payout amount.
    @param participants The ordered cohort addresses.
    @return uint256 The new ERC-1155 / pasanaku id.
    """
    return convert(
        keccak256(abi_encode(asset, amount, participants, block.prevhash)),
        uint256,
    )
