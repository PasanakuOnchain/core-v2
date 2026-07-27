# pragma version ~=0.4.3
# pragma nonreentrancy on
"""
@title Pasanaku
@custom:contract-name pasanaku
@notice Collateral-backed rotating savings pools using ERC-4626 shares.
@license GNU Affero General Public License v3.0 only
@author rafael-abuawad
"""


from ethereum.ercs import IERC20


from ethereum.ercs import IERC4626


from ethereum.ercs import IERC165
implements: IERC165


from snekmate.tokens.interfaces import IERC1155
implements: IERC1155


from snekmate.tokens.interfaces import IERC1155MetadataURI
implements: IERC1155MetadataURI


from snekmate.auth import ownable as ow
initializes: ow


from snekmate.auth import ownable_2step as ow2step
initializes: ow2step[ownable := ow]


from snekmate.tokens import erc1155
initializes: erc1155[ownable := ow]


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


_DAYS_3: constant(uint256) = 3 * 24 * 60 * 60


_DAYS_7: constant(uint256) = 7 * 24 * 60 * 60


_DAYS_40: constant(uint256) = 40 * 24 * 60 * 60


_MIN_PARTICIPANT_COUNT: constant(uint256) = 6


_MAX_PARTICIPANT_COUNT: constant(uint256) = 12


_BPS_PRECISION: constant(uint256) = 10_000


_MISS_PENALTY_BPS: constant(uint256) = 5


_TOKEN_AMOUNT: constant(uint256) = 1


_MAX_FEE: constant(uint256) = as_wei_value(0.001, "ether")


_ASSET: immutable(IERC20)


_VAULT: immutable(IERC4626)


struct Pasanaku:
    round_assets: uint256
    participant_count: uint256
    participants: DynArray[address, _MAX_PARTICIPANT_COUNT]
    index: uint256
    created: uint256
    started: uint256
    updated: uint256
    ended: uint256


_counter: uint256


_pasanakus: HashMap[uint256, Pasanaku]


_free_shares: HashMap[address, uint256]


_locked_shares: HashMap[uint256, HashMap[address, uint256]]


_locked_asset_basis: HashMap[uint256, HashMap[address, uint256]]


_pool_reserve_shares: HashMap[uint256, uint256]


_deposited_for_pasanaku: HashMap[
    uint256, HashMap[uint256, HashMap[address, bool]]
]


_successful_obligated_deposits: HashMap[
    uint256, HashMap[address, uint256]
]


_pool_escrow: HashMap[uint256, uint256]


_pending_payout: HashMap[uint256, HashMap[uint256, uint256]]


_active_pasanaku_count: uint256


_stale_time: uint256


_fee: uint256


event CollateralDeposited:
    receiver: indexed(address)
    assets: uint256
    shares: uint256


event CollateralWithdrawn:
    owner: indexed(address)
    receiver: indexed(address)
    assets: uint256
    shares: uint256


event CollateralRedeemed:
    owner: indexed(address)
    receiver: indexed(address)
    assets: uint256
    shares: uint256


event PasanakuCreated:
    token_id: indexed(uint256)
    round_assets: uint256
    participant_count: uint256


event PasanakuJoined:
    token_id: indexed(uint256)
    account: indexed(address)
    joined_count: uint256


event PasanakuLeft:
    token_id: indexed(uint256)
    account: indexed(address)
    joined_count: uint256


event PasanakuStarted:
    token_id: indexed(uint256)
    round_assets: uint256
    participant_count: uint256
    started_at: uint256


event PasanakuDeposited:
    account: indexed(address)
    token_id: indexed(uint256)
    index: uint256
    amount: uint256


event PasanakuTicked:
    token_id: indexed(uint256)
    tick_index: uint256
    recipient: indexed(address)
    amount: uint256
    updated_at: uint256


event PasanakuReserved:
    token_id: indexed(uint256)
    tick_index: uint256
    account: indexed(address)
    assets: uint256
    shares: uint256


event PasanakuSurplusDistributed:
    token_id: indexed(uint256)
    surplus_shares: uint256
    shares_per_participant: uint256


event PasanakuEnded:
    token_id: indexed(uint256)
    round_assets: uint256
    ended_at: uint256


event StaleTimeSet:
    stale_time: uint256


event FeeSet:
    fee: uint256


event FeesCollected:
    target: indexed(address)
    amount: uint256


@deploy
@payable
def __init__(asset_: IERC20, vault_: IERC4626, fee_: uint256):
    assert asset_ != empty(IERC20)  # dev: invalid asset
    assert vault_ != empty(IERC4626)  # dev: invalid vault
    assert staticcall vault_.asset() == asset_.address  # dev: bad asset+vault configuration
    assert fee_ <= _MAX_FEE  # dev: fee is out of range

    _ASSET = asset_
    _VAULT = vault_
    self._stale_time = _DAYS_7
    self._fee = fee_

    ow.__init__()
    ow2step.__init__()
    erc1155.__init__("")

    log FeeSet(fee=fee_)


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
    assert msg.value >= self._fee  # dev: insufficient fee

    token_id: uint256 = self._counter
    self._counter += 1

    pasanaku: Pasanaku = empty(Pasanaku)
    pasanaku.round_assets = round_assets
    pasanaku.participant_count = participant_count
    pasanaku.participants.append(msg.sender)
    pasanaku.created = block.timestamp
    self._pasanakus[token_id] = pasanaku

    self._lock_pledge(
        token_id, msg.sender, round_assets, participant_count
    )

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
    assert pasanaku.created + self._stale_time <= block.timestamp  # dev: pasanaku is not stale
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
    assert pasanaku.updated + _DAYS_40 <= block.timestamp  # dev: not enough time passed

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
    assert stale_time >= _DAYS_3 and stale_time <= _DAYS_7  # dev: stale time out of range
    self._stale_time = stale_time
    log StaleTimeSet(stale_time=stale_time)


@external
def set_fee(fee_: uint256):
    ow._check_owner()
    assert fee_ <= _MAX_FEE  # dev: fee is out of range
    self._fee = fee_
    log FeeSet(fee=fee_)


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
    elif pasanaku.created + self._stale_time <= block.timestamp:
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
    penalty_assets: uint256 = (
        amount * _MISS_PENALTY_BPS // _BPS_PRECISION
    )
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

        withdraw_preview: uint256 = staticcall _VAULT.previewWithdraw(amount)
        penalty_shares: uint256 = 0
        if penalty_assets > 0:
            penalty_shares = staticcall _VAULT.previewWithdraw(
                penalty_assets
            )
        assert self._locked_shares[token_id][participant] >= withdraw_preview + penalty_shares  # dev: insufficient locked shares

        burned_shares: uint256 = extcall _VAULT.withdraw(
            amount, self, self
        )
        assert self._locked_shares[token_id][participant] >= burned_shares + penalty_shares  # dev: insufficient locked shares
        self._locked_shares[token_id][participant] -= (
            burned_shares + penalty_shares
        )
        self._locked_asset_basis[token_id][participant] -= (
            amount + penalty_assets
        )
        self._pool_reserve_shares[token_id] += penalty_shares
        self._pool_escrow[token_id] += amount
        recipient_payout += amount

        log PasanakuReserved(
            token_id=token_id,
            tick_index=round_idx,
            account=participant,
            assets=penalty_assets,
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
