# pragma version ~=0.4.3
# pragma nonreentrancy on
"""
@title Pasanaku
@custom:contract-name pasanaku
@notice Collateral-backed rotating savings pools using ERC-4626 shares.
@license GNU Affero General Public License v3.0 only
@author rafael-abuawad
"""

# @dev Underlying ERC-20 asset interface.
from ethereum.ercs import IERC20


# @dev ERC-4626 vault interface for share accounting.
from ethereum.ercs import IERC4626


# @dev ERC-165 interface detection.
from ethereum.ercs import IERC165
implements: IERC165


# @dev ERC-1155 multi-token standard (membership tokens).
from snekmate.tokens.interfaces import IERC1155
implements: IERC1155


# @dev ERC-1155 metadata URI extension.
from snekmate.tokens.interfaces import IERC1155MetadataURI
implements: IERC1155MetadataURI


# @dev Ownable access control (base for two-step ownership).
from snekmate.auth import ownable as ow
initializes: ow


# @dev Two-step ownership transfer.
from snekmate.auth import ownable_2step as ow2step
initializes: ow2step[ownable := ow]


# @dev ERC-1155 token logic (balances, supply, transfers).
from snekmate.tokens import erc1155
initializes: erc1155[ownable := ow]


# @dev Re-export ownership and selected ERC-1155 view helpers.
exports: (
    ow2step.owner,
    ow2step.pending_owner,
    ow2step.transfer_ownership,
    ow2step.accept_ownership,
    ow2step.renounce_ownership,
    erc1155.supportsInterface,
    erc1155.balanceOfBatch,
    erc1155.exists,
    erc1155.total_supply,
)


# @dev Lower bound for configurable stale timeout (seconds).
_3_DAYS: constant(uint256) = 3 * 24 * 60 * 60


# @dev Upper bound for configurable stale timeout (seconds).
_7_DAYS: constant(uint256) = 7 * 24 * 60 * 60


# @dev Minimum interval between ticks / rounds (seconds).
_40_DAYS: constant(uint256) = 40 * 24 * 60 * 60


# @dev Allowed participant counts are exactly 6 or 12 (not a range).
_MIN_PARTICIPANT_COUNT: constant(uint256) = 6


_MAX_PARTICIPANT_COUNT: constant(uint256) = 12


# @dev Basis-point denominator (100% = 10_000).
_BPS_PRECISION: constant(uint256) = 10_000


# @dev Miss penalty: 5 BPS (0.05%).
_MISS_PENALTY_BPS: constant(uint256) = 5


# @dev Maximum yield fee: 505 BPS (5.05%).
_MAX_YIELD_FEE: constant(uint256) = 505


# @dev Membership tokens minted per participant per pasanaku.
_TOKEN_AMOUNT: constant(uint256) = 1


# @dev Cap on creation fee (wei).
_MAX_FEE: constant(uint256) = as_wei_value(0.001, "ether")


# @dev Supported ERC-20 asset (set at deploy).
_ASSET: immutable(IERC20)


# @dev Supported ERC-4626 vault (set at deploy).
_VAULT: immutable(IERC4626)


# @dev Fixed-membership rotating savings pool identified by `token_id`.
# - round_assets: Per-round deposit obligation in underlying asset units.
# - participant_count: Target size: exactly 6 or 12.
# - participants: Shuffled roster; index `k` is the recipient of round `k`.
# - index: Next round to settle via `tick`.
# - created: Timestamp when the pool was created.
# - stale_time: Exit timeout snapshotted when the pool was created.
# - started: Timestamp when membership locked and rounds began (`0` = not started).
# - updated: Timestamp of the last successful `tick`.
# - ended: Timestamp when the final round settled (`0` = still active).
struct Pasanaku:
    round_assets: uint256
    participant_count: uint256
    participants: DynArray[address, _MAX_PARTICIPANT_COUNT]
    index: uint256
    created: uint256
    stale_time: uint256
    started: uint256
    updated: uint256
    ended: uint256


# @dev Next `token_id` to assign; also upper bound for valid ids.
_counter: uint256


# @dev Pool state keyed by `token_id`.
_pasanakus: HashMap[uint256, Pasanaku]


# @dev Unlocked vault shares withdrawable or pledgeable by the user.
_free_shares: HashMap[address, uint256]


# @dev Vault shares pledged as collateral to a specific pool.
_locked_shares: HashMap[uint256, HashMap[address, uint256]]


# @dev Fixed underlying-asset principal basis for locked collateral (not a live balance).
_locked_asset_basis: HashMap[uint256, HashMap[address, uint256]]


# @dev Miss-penalty shares owned by the pool (distributed at end).
_pool_reserve_shares: HashMap[uint256, uint256]


# @dev Whether `address` already deposited for `token_id` / round.
_deposited_for_pasanaku: HashMap[
    uint256, HashMap[uint256, HashMap[address, bool]]
]


# @dev Count of successful obligated deposits per participant per pool.
_successful_obligated_deposits: HashMap[
    uint256, HashMap[address, uint256]
]


# @dev Liquid underlying held for the current round payout.
_pool_escrow: HashMap[uint256, uint256]


# @dev Claimable round payout: `token_id` -> round -> amount.
_pending_payout: HashMap[uint256, HashMap[uint256, uint256]]


# @dev Number of started, not-yet-ended pools.
_active_pasanaku_count: uint256


# @dev Max age after `created` before an unstarted pool can be left as stale.
_stale_time: uint256


# @dev Creation fee in wei (paid as `msg.value`).
_fee: uint256


# @dev Distribution fee in basis-points.
_yield_fee: uint256


# @dev Emitted when underlying assets are deposited into the vault as free shares.
event CollateralDeposited:
    receiver: indexed(address)
    assets: uint256
    shares: uint256


# @dev Emitted when free shares are burned to withdraw an exact asset amount.
event CollateralWithdrawn:
    owner: indexed(address)
    receiver: indexed(address)
    assets: uint256
    shares: uint256


# @dev Emitted when an exact amount of free shares is redeemed for assets.
event CollateralRedeemed:
    owner: indexed(address)
    receiver: indexed(address)
    assets: uint256
    shares: uint256


# @dev Emitted when a new pasanaku pool is created.
event PasanakuCreated:
    token_id: indexed(uint256)
    round_assets: uint256
    participant_count: uint256


# @dev Emitted when an account joins a pasanaku before it starts.
event PasanakuJoined:
    token_id: indexed(uint256)
    account: indexed(address)
    joined_count: uint256


# @dev Emitted when an account leaves a stale, unstarted pasanaku.
event PasanakuLeft:
    token_id: indexed(uint256)
    account: indexed(address)
    joined_count: uint256


# @dev Emitted when a pasanaku fills and membership locks in.
event PasanakuStarted:
    token_id: indexed(uint256)
    round_assets: uint256
    participant_count: uint256
    started_at: uint256


# @dev Emitted when a participant makes their obligated round deposit.
event PasanakuDeposited:
    account: indexed(address)
    token_id: indexed(uint256)
    index: uint256
    amount: uint256


# @dev Emitted when a round is settled and the recipient's payout is accrued.
event PasanakuTicked:
    token_id: indexed(uint256)
    tick_index: uint256
    recipient: indexed(address)
    amount: uint256
    updated_at: uint256


# @dev Emitted when a missed deposit is covered from locked collateral into the reserve.
event PasanakuReserved:
    token_id: indexed(uint256)
    tick_index: uint256
    account: indexed(address)
    assets: uint256
    shares: uint256


# @dev Emitted when leftover reserve / surplus shares are split among participants.
event PasanakuSurplusDistributed:
    token_id: indexed(uint256)
    surplus_shares: uint256
    shares_per_participant: uint256


# @dev Emitted when the final round settles and the pool ends.
event PasanakuEnded:
    token_id: indexed(uint256)
    round_assets: uint256
    ended_at: uint256


# @dev Emitted when the admin updates the stale timeout.
event StaleTimeSet:
    stale_time: uint256


# @dev Emitted when the admin updates the creation fee.
event FeeSet:
    fee: uint256


# @dev Emitted when the admin updates the yield fee.
event YieldFeeSet:
    fee: uint256


# @dev Emitted when accrued creation fees are withdrawn.
event FeesCollected:
    target: indexed(address)
    amount: uint256


@deploy
@payable
def __init__(asset_: IERC20, vault_: IERC4626, fee_: uint256, yield_fee_: uint256):
    assert asset_ != empty(IERC20)  # dev: invalid asset
    assert vault_ != empty(IERC4626)  # dev: invalid vault
    assert staticcall vault_.asset() == asset_.address  # dev: bad asset+vault configuration
    assert fee_ <= _MAX_FEE  # dev: fee is out of range
    assert yield_fee_ <= _MAX_YIELD_FEE  # dev: yield fee is out of range

    _ASSET = asset_
    _VAULT = vault_
    self._stale_time = _7_DAYS
    self._fee = fee_
    self._yield_fee = yield_fee_

    ow.__init__()
    ow2step.__init__()
    erc1155.__init__("")

    log FeeSet(fee=fee_)
    log YieldFeeSet(fee=fee_)


@external
def deposit(assets: uint256, receiver: address) -> uint256:
    assert assets > 0  # dev: invalid assets amount
    assert receiver != empty(address)  # dev: invalid receiver

    success: bool = extcall _ASSET.transferFrom(
        msg.sender, self, assets, default_return_value=True
    )
    assert success  # dev: transferFrom failed
    success = extcall _ASSET.approve(
        _VAULT.address, assets, default_return_value=True
    )
    assert success  # dev: approve failed

    shares: uint256 = extcall _VAULT.deposit(assets, self)
    assert shares > 0  # dev: erc4626 deposit failed
    self._free_shares[receiver] += shares

    log CollateralDeposited(receiver=receiver, assets=assets, shares=shares)
    return shares


@external
def withdraw(assets: uint256, receiver: address) -> uint256:
    assert assets > 0  # dev: invalid assets amount
    assert receiver != empty(address)  # dev: invalid receiver

    preview_shares: uint256 = staticcall _VAULT.previewWithdraw(assets)
    assert self._free_shares[msg.sender] >= preview_shares  # dev: insufficient free shares

    shares: uint256 = extcall _VAULT.withdraw(assets, receiver, self)
    assert self._free_shares[msg.sender] >= shares  # dev: insufficient free shares
    self._free_shares[msg.sender] -= shares

    log CollateralWithdrawn(
        owner=msg.sender,
        receiver=receiver,
        assets=assets,
        shares=shares,
    )
    return shares


@external
def redeem(shares: uint256, receiver: address) -> uint256:
    assert shares > 0  # dev: invalid shares amount
    assert receiver != empty(address)  # dev: invalid receiver
    assert self._free_shares[msg.sender] >= shares  # dev: insufficient free shares

    assets: uint256 = extcall _VAULT.redeem(shares, receiver, self)
    self._free_shares[msg.sender] -= shares

    log CollateralRedeemed(
        owner=msg.sender,
        receiver=receiver,
        assets=assets,
        shares=shares,
    )
    return assets


@external
@payable
def create_pasanaku(
    round_assets: uint256, participant_count: uint256
) -> uint256:
    assert round_assets > 0  # dev: invalid amount
    assert self._valid_participant_count(participant_count)  # dev: invalid participant count
    fee: uint256 = self._fee
    assert msg.value >= fee  # dev: insufficient fee

    token_id: uint256 = self._counter
    self._counter += 1

    pasanaku: Pasanaku = empty(Pasanaku)
    pasanaku.round_assets = round_assets
    pasanaku.participant_count = participant_count
    pasanaku.participants.append(msg.sender)
    pasanaku.created = block.timestamp
    pasanaku.stale_time = self._stale_time
    self._pasanakus[token_id] = pasanaku

    self._lock_pledge(
        token_id, msg.sender, round_assets, participant_count
    )

    if msg.value > fee:
        surplus: uint256 = msg.value - fee
        success: bool = raw_call(
            msg.sender,
            b"",
            max_outsize=0,
            value=surplus,
            revert_on_failure=False,
        )
        assert success  # dev: fee transfer failed

    log PasanakuCreated(
        token_id=token_id,
        round_assets=round_assets,
        participant_count=participant_count,
    )
    return token_id


@external
def deposit_to_pasanaku(amount: uint256, token_id: uint256):
    assert amount > 0  # dev: invalid amount
    assert token_id < self._counter  # dev: invalid token id

    pasanaku: Pasanaku = self._pasanakus[token_id]
    round_idx: uint256 = pasanaku.index
    assert pasanaku.started != 0  # dev: pasanaku not started
    assert pasanaku.ended == 0  # dev: pasanaku ended
    assert msg.sender in pasanaku.participants  # dev: account not in pasanaku
    assert msg.sender != pasanaku.participants[round_idx]  # dev: active participant cannot deposit
    assert not self._deposited_for_pasanaku[token_id][round_idx][msg.sender]  # dev: account already deposited
    assert amount == pasanaku.round_assets  # dev: invalid deposit amount

    success: bool = extcall _ASSET.transferFrom(
        msg.sender, self, amount, default_return_value=True
    )
    assert success  # dev: transferFrom failed

    self._deposited_for_pasanaku[token_id][round_idx][msg.sender] = True
    self._successful_obligated_deposits[token_id][msg.sender] += 1
    self._pool_escrow[token_id] += amount

    log PasanakuDeposited(
        account=msg.sender,
        token_id=token_id,
        index=round_idx,
        amount=amount,
    )


@external
def join_pasanaku(token_id: uint256):
    assert token_id < self._counter  # dev: invalid token id

    pasanaku: Pasanaku = self._pasanakus[token_id]
    assert pasanaku.started == 0  # dev: pasanaku already started
    assert (
        block.timestamp < pasanaku.created + pasanaku.stale_time
    )  # dev: pasanaku is stale
    assert msg.sender not in pasanaku.participants  # dev: participant already joined
    assert len(pasanaku.participants) < pasanaku.participant_count  # dev: pasanaku full

    self._lock_pledge(
        token_id,
        msg.sender,
        pasanaku.round_assets,
        pasanaku.participant_count,
    )
    pasanaku.participants.append(msg.sender)
    self._pasanakus[token_id] = pasanaku

    log PasanakuJoined(
        token_id=token_id,
        account=msg.sender,
        joined_count=len(pasanaku.participants),
    )

    if len(pasanaku.participants) == pasanaku.participant_count:
        self._start_pasanaku(token_id)


@external
def leave_pasanaku(token_id: uint256):
    assert token_id < self._counter  # dev: invalid token id

    pasanaku: Pasanaku = self._pasanakus[token_id]
    assert pasanaku.started == 0  # dev: pasanaku already started
    assert (
        pasanaku.created + pasanaku.stale_time <= block.timestamp
    )  # dev: pasanaku is not stale
    assert msg.sender in pasanaku.participants  # dev: participant not in pasanaku

    locked: uint256 = self._locked_shares[token_id][msg.sender]
    self._locked_shares[token_id][msg.sender] = 0
    self._locked_asset_basis[token_id][msg.sender] = 0
    self._free_shares[msg.sender] += locked

    pasanaku.participants = self._remove_from_array(
        pasanaku.participants, msg.sender
    )
    self._pasanakus[token_id] = pasanaku

    log PasanakuLeft(
        token_id=token_id,
        account=msg.sender,
        joined_count=len(pasanaku.participants),
    )


@external
def tick(token_id: uint256):
    assert token_id < self._counter  # dev: invalid token id
    pasanaku: Pasanaku = self._pasanakus[token_id]
    assert pasanaku.started != 0  # dev: pasanaku not started
    assert pasanaku.ended == 0  # dev: pasanaku ended
    assert pasanaku.updated + _40_DAYS <= block.timestamp  # dev: not enough time passed

    round_idx: uint256 = pasanaku.index
    recipient: address = pasanaku.participants[round_idx]
    recipient_payout: uint256 = self._settle_round(
        token_id, round_idx, recipient
    )
    self._accrue_recipient_payout(
        token_id, round_idx, recipient_payout
    )

    pasanaku.updated = block.timestamp
    pasanaku.index += 1

    log PasanakuTicked(
        token_id=token_id,
        tick_index=round_idx,
        recipient=recipient,
        amount=recipient_payout,
        updated_at=block.timestamp,
    )

    if round_idx == pasanaku.participant_count - 1:
        pasanaku.ended = block.timestamp
        self._pasanakus[token_id] = pasanaku
        self._settle_pool_collateral(token_id)
        self._active_pasanaku_count -= 1
        log PasanakuEnded(
            token_id=token_id,
            round_assets=pasanaku.round_assets,
            ended_at=block.timestamp,
        )
    else:
        self._pasanakus[token_id] = pasanaku


@external
def claim_round_payout(token_id: uint256, round_idx: uint256):
    assert token_id < self._counter  # dev: invalid token id
    pasanaku: Pasanaku = self._pasanakus[token_id]
    assert round_idx < pasanaku.participant_count  # dev: invalid round
    recipient: address = pasanaku.participants[round_idx]
    assert msg.sender == recipient  # dev: not recipient

    amount: uint256 = self._pending_payout[token_id][round_idx]
    assert amount > 0  # dev: no pending payout
    self._pending_payout[token_id][round_idx] = 0
    success: bool = extcall _ASSET.transfer(
        recipient, amount, default_return_value=True
    )
    assert success  # dev: transfer failed


@external
def set_stale_time(stale_time: uint256):
    ow._check_owner()
    assert stale_time >= _3_DAYS and stale_time <= _7_DAYS  # dev: stale time out of range
    self._stale_time = stale_time
    log StaleTimeSet(stale_time=stale_time)


@external
def set_fee(fee_: uint256):
    ow._check_owner()
    assert fee_ <= _MAX_FEE  # dev: fee is out of range
    self._fee = fee_
    log FeeSet(fee=fee_)


@external
def set_yield_fee(yield_fee_: uint256):
    ow._check_owner()
    assert yield_fee_ <= _MAX_YIELD_FEE  # dev: fee is out of range
    self._yield_fee = yield_fee_
    log YieldFeeSet(fee=yield_fee_)


@external
def collect_fees():
    amount: uint256 = self.balance
    success: bool = raw_call(
        ow.owner,
        b"",
        max_outsize=0,
        value=amount,
        revert_on_failure=False,
    )
    assert success  # dev: fee transfer failed
    log FeesCollected(target=ow.owner, amount=amount)


@external
def safeTransferFrom(
    owner: address,
    to: address,
    id: uint256,
    amount: uint256,
    data: Bytes[1024],
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
def uri(token_id: uint256) -> String[512]:
    if token_id >= self._counter:
        return "ipfs://QmbcELYwEiVu6n6nJhHmdqTRPfWD6eNHiXZhixKvhjAznF"

    pasanaku: Pasanaku = self._pasanakus[token_id]
    if pasanaku.ended != 0:
        return "ipfs://QmYA1EK6dEujhcdZMWbjk1gVoHyqEYDZoptHMzL8ppTfWH"
    elif pasanaku.started != 0:
        return "ipfs://QmYvMoHxQSPLbCaofRHEyskb7U5UEyq31gwH9pyM1WSEc4"
    elif pasanaku.created + pasanaku.stale_time <= block.timestamp:
        return "ipfs://QmcGBA3PSwZxq6RQQsWbUe4NNtbLCbaxuVpx1Jnv5qRF98"
    return "ipfs://QmZ9PeXU9sUbax7SPAbyoBZawNqCrdgtEYXdipzMYi4Rsp"


@external
@view
def isApprovedForAll(owner: address, operator: address) -> bool:
    return False


@external
@view
def pasanaku(token_id: uint256) -> Pasanaku:
    return self._pasanakus[token_id]


@external
@view
def deposited_for_pasanaku(
    token_id: uint256, index: uint256, participant: address
) -> bool:
    return self._deposited_for_pasanaku[token_id][index][participant]


@external
@view
def successful_obligated_deposits(
    token_id: uint256, participant: address
) -> uint256:
    return self._successful_obligated_deposits[token_id][participant]


@external
@view
def asset() -> address:
    return _ASSET.address


@external
@view
def vault() -> address:
    return _VAULT.address


@external
@view
def active_pasanaku_count() -> uint256:
    return self._active_pasanaku_count


@external
@view
def free_shares(participant: address) -> uint256:
    return self._free_shares[participant]


@external
@view
def locked_shares(token_id: uint256, participant: address) -> uint256:
    return self._locked_shares[token_id][participant]


@external
@view
def locked_asset_basis(
    token_id: uint256, participant: address
) -> uint256:
    return self._locked_asset_basis[token_id][participant]


@external
@view
def pool_reserve_shares(token_id: uint256) -> uint256:
    return self._pool_reserve_shares[token_id]


@external
@view
def balanceOf(account: address, id: uint256) -> uint256:
    return erc1155.balanceOf[account][id]


@external
@view
def pool_escrow(token_id: uint256) -> uint256:
    return self._pool_escrow[token_id]


@external
@view
def pending_payout(token_id: uint256, round_idx: uint256) -> uint256:
    return self._pending_payout[token_id][round_idx]


@external
@view
def fee() -> uint256:
    return self._fee


@external
@view
def stale_time() -> uint256:
    return self._stale_time


@external
@pure
def pledge(round_assets: uint256, participant_count: uint256) -> uint256:
    assert self._valid_participant_count(participant_count)  # dev: invalid participant count
    return self._pledge(round_assets, participant_count)


@internal
@pure
def _valid_participant_count(participant_count: uint256) -> bool:
    return (
        participant_count == _MIN_PARTICIPANT_COUNT
        or participant_count == _MAX_PARTICIPANT_COUNT
    )


@internal
@pure
def _pledge(round_assets: uint256, participant_count: uint256) -> uint256:
    principal: uint256 = round_assets * participant_count
    penalties: uint256 = (
        principal * _MISS_PENALTY_BPS // _BPS_PRECISION
    )
    return principal + penalties


@internal
def _lock_pledge(
    token_id: uint256,
    participant: address,
    round_assets: uint256,
    participant_count: uint256,
):
    assets: uint256 = self._pledge(round_assets, participant_count)
    shares: uint256 = staticcall _VAULT.previewWithdraw(assets)
    assert self._free_shares[participant] >= shares  # dev: insufficient free shares
    self._free_shares[participant] -= shares
    self._locked_shares[token_id][participant] = shares


@internal
def _start_pasanaku(token_id: uint256):
    pasanaku: Pasanaku = self._pasanakus[token_id]
    random_seed: uint256 = convert(
        keccak256(abi_encode(block.prevrandao, block.timestamp, token_id)),
        uint256,
    )
    pasanaku.participants = self._shuffle_array(
        random_seed, pasanaku.participants
    )
    pledge_assets: uint256 = self._pledge(
        pasanaku.round_assets, pasanaku.participant_count
    )
    target_shares: uint256 = staticcall _VAULT.previewWithdraw(
        pledge_assets
    )

    for i: uint256 in range(
        pasanaku.participant_count, bound=_MAX_PARTICIPANT_COUNT
    ):
        participant: address = pasanaku.participants[i]
        locked: uint256 = self._locked_shares[token_id][participant]
        if locked > target_shares:
            self._free_shares[participant] += locked - target_shares
        elif locked < target_shares:
            top_up: uint256 = target_shares - locked
            assert self._free_shares[participant] >= top_up  # dev: pre-start collateral loss
            self._free_shares[participant] -= top_up
        self._locked_shares[token_id][participant] = target_shares
        self._locked_asset_basis[token_id][participant] = pledge_assets
        self._mint_membership_token(participant, token_id)

    pasanaku.started = block.timestamp
    pasanaku.updated = block.timestamp
    self._pasanakus[token_id] = pasanaku
    self._active_pasanaku_count += 1

    log PasanakuStarted(
        token_id=token_id,
        round_assets=pasanaku.round_assets,
        participant_count=pasanaku.participant_count,
        started_at=block.timestamp,
    )


@internal
def _mint_membership_token(owner: address, token_id: uint256):
    erc1155.total_supply[token_id] += _TOKEN_AMOUNT
    erc1155.balanceOf[owner][token_id] += _TOKEN_AMOUNT
    log IERC1155.TransferSingle(
        _operator=msg.sender,
        _from=empty(address),
        _to=owner,
        _id=token_id,
        _value=_TOKEN_AMOUNT,
    )


@internal
def _settle_round(
    token_id: uint256, round_idx: uint256, recipient: address
) -> uint256:
    pasanaku: Pasanaku = self._pasanakus[token_id]
    amount: uint256 = pasanaku.round_assets
    penalty_assets: uint256 = amount * _MISS_PENALTY_BPS // _BPS_PRECISION
    recipient_payout: uint256 = 0

    for i: uint256 in range(
        pasanaku.participant_count, bound=_MAX_PARTICIPANT_COUNT
    ):
        participant: address = pasanaku.participants[i]
        if participant == recipient:
            continue
        if self._deposited_for_pasanaku[token_id][round_idx][participant]:
            recipient_payout += amount
            continue

        needed_shares: uint256 = staticcall _VAULT.previewWithdraw(
            amount + penalty_assets
        )
        locked: uint256 = self._locked_shares[token_id][participant]
        penalty_shares: uint256 = 0
        reserved_assets: uint256 = 0
        funded_assets: uint256 = 0

        if locked < needed_shares:
            if locked > 0:
                funded_assets = extcall _VAULT.redeem(
                    locked, self, self
                )
            self._locked_shares[token_id][participant] = 0
            self._locked_asset_basis[token_id][participant] = 0
        else:
            burned_shares: uint256 = extcall _VAULT.withdraw(
                amount, self, self
            )
            assert needed_shares >= burned_shares  # dev: bad vault preview
            penalty_shares = needed_shares - burned_shares
            self._locked_shares[token_id][participant] -= needed_shares
            self._locked_asset_basis[token_id][participant] -= (
                amount + penalty_assets
            )
            self._pool_reserve_shares[token_id] += penalty_shares
            reserved_assets = penalty_assets
            funded_assets = amount

        self._pool_escrow[token_id] += funded_assets
        recipient_payout += funded_assets

        log PasanakuReserved(
            token_id=token_id,
            tick_index=round_idx,
            account=participant,
            assets=reserved_assets,
            shares=penalty_shares,
        )

    return recipient_payout


@internal
def _accrue_recipient_payout(
    token_id: uint256, round_idx: uint256, payout: uint256
):
    assert self._pool_escrow[token_id] >= payout  # dev: insufficient escrow
    self._pool_escrow[token_id] -= payout
    self._pending_payout[token_id][round_idx] += payout


@internal
def _settle_pool_collateral(token_id: uint256):
    pasanaku: Pasanaku = self._pasanakus[token_id]
    total_shortfall: uint256 = 0

    for i: uint256 in range(
        pasanaku.participant_count, bound=_MAX_PARTICIPANT_COUNT
    ):
        participant: address = pasanaku.participants[i]
        basis: uint256 = self._locked_asset_basis[token_id][participant]
        required: uint256 = 0
        if basis > 0:
            required = staticcall _VAULT.previewWithdraw(basis)
        locked: uint256 = self._locked_shares[token_id][participant]
        if required > locked:
            total_shortfall += required - locked

    reserve: uint256 = self._pool_reserve_shares[token_id]
    available_reserve: uint256 = min(reserve, total_shortfall)
    reserve_remaining: uint256 = available_reserve
    shortfall_remaining: uint256 = total_shortfall
    surplus: uint256 = reserve - available_reserve

    for i: uint256 in range(
        pasanaku.participant_count, bound=_MAX_PARTICIPANT_COUNT
    ):
        participant: address = pasanaku.participants[i]
        basis: uint256 = self._locked_asset_basis[token_id][participant]
        required: uint256 = 0
        if basis > 0:
            required = staticcall _VAULT.previewWithdraw(basis)
        locked: uint256 = self._locked_shares[token_id][participant]
        returned: uint256 = locked

        if locked >= required:
            returned = required
            surplus += locked - required
        else:
            shortfall: uint256 = required - locked
            allocation: uint256 = 0
            if shortfall == shortfall_remaining:
                allocation = reserve_remaining
            elif total_shortfall > 0:
                allocation = (
                    shortfall * available_reserve // total_shortfall
                )
            returned += allocation
            reserve_remaining -= allocation
            shortfall_remaining -= shortfall

        self._free_shares[participant] += returned
        self._locked_shares[token_id][participant] = 0
        self._locked_asset_basis[token_id][participant] = 0

    self._pool_reserve_shares[token_id] = 0
    shares_per_participant: uint256 = (
        surplus // pasanaku.participant_count
    )
    dust: uint256 = surplus % pasanaku.participant_count

    for i: uint256 in range(
        pasanaku.participant_count, bound=_MAX_PARTICIPANT_COUNT
    ):
        participant: address = pasanaku.participants[i]
        self._free_shares[participant] += shares_per_participant
        if i == pasanaku.participant_count - 1:
            self._free_shares[participant] += dust

    log PasanakuSurplusDistributed(
        token_id=token_id,
        surplus_shares=surplus,
        shares_per_participant=shares_per_participant,
    )


@internal
@pure
def _remove_from_array(
    participants: DynArray[address, _MAX_PARTICIPANT_COUNT],
    target: address,
) -> DynArray[address, _MAX_PARTICIPANT_COUNT]:
    length: uint256 = len(participants)
    assert length > 0  # dev: empty participants

    found: bool = False
    last_idx: uint256 = length - 1
    last_participant: address = participants[last_idx]
    for i: uint256 in range(length, bound=_MAX_PARTICIPANT_COUNT):
        if participants[i] == target:
            participants[i] = last_participant
            found = True
            break

    assert found  # dev: participant not in pasanaku
    participants.pop()
    return participants


@internal
@pure
def _shuffle_array(
    random_seed: uint256,
    participants: DynArray[address, _MAX_PARTICIPANT_COUNT]
) -> DynArray[address, _MAX_PARTICIPANT_COUNT]:
    length: uint256 = len(participants)
    if length < 1:
        return participants

    seed: uint256 = random_seed
    for i: uint256 in range(_MAX_PARTICIPANT_COUNT):
        if i >= length - 1:
            break

        remaining: uint256 = length - i
        seed = convert(keccak256(abi_encode(seed, i)), uint256)
        j: uint256 = i + (seed % remaining)

        tmp: address = participants[i]
        participants[i] = participants[j]
        participants[j] = tmp
    return participants
