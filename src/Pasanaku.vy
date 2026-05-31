# pragma version ~=0.4.3
# pragma nonreentrancy off
"""
@title Pasanaku
@custom:contract-name pasanaku
@notice Rotating savings pool with collateral-backed rounds.
@license GNU Affero General Public License v3.0 only
@author rafael-abuawad

@dev Supported assets constructor triple is deployment-specific canonical ERC20 addresses
      (intended identities: wstETH, USDC, USDT, GHO on the target chain). Standard transfer
      semantics only — no fee on transfer or rebasing; internal balances match IERC20 movers.

Protocol summary:
    • N = _PARTICIPANT_COUNT participants; creator joins first; pool starts full.
    • Window index k equals pasanaku.index before tick: recipient is participants[k];
      all other participants must deposit pasanaku.amount for that k (recipient exempt).
    • Each tick (after _DAYS_40): settle round k — recipient receives (N-1)*amount in principal.
      Non-recipients who did not deposit lose amount plus a miss penalty (bps) from
      _collateral; principal fills the pool. All forfeited penalty ERC20 goes to owner()
      (treasury); `PasanakuPenalties` logs the amount.
    • Obligor deposits: underlying ERC20 is held on-contract as escrow until tick pays the
      round recipient.
    • One active pasanaku per supported asset: only a started, not-yet-ended pool may hold
      the active slot; pending pools for the same asset may coexist.
    • Join/create lock pledge(amount) = amount*N + amount*N*PENALTY_BPS//10000 into _collateral_in_use.
"""

from ethereum.ercs import IERC20

from ethereum.ercs import IERC165
implements: IERC165

from snekmate.tokens.interfaces import IERC1155
implements: IERC1155

from snekmate.tokens.interfaces import IERC1155MetadataURI
implements: IERC1155MetadataURI

from snekmate.tokens import erc1155
initializes: erc1155[ownable := ow]

from snekmate.auth import ownable as ow
initializes: ow

from snekmate.auth import ownable_2step as ow2step
initializes: ow2step[ownable := ow]

exports: (
    ow2step.owner,
    ow2step.pending_owner,
    ow2step.transfer_ownership,
    ow2step.accept_ownership,
    ow2step.renounce_ownership,
    erc1155.supportsInterface,
    erc1155.balanceOfBatch,
    erc1155.exists,
    erc1155.balanceOf,
    erc1155.total_supply,
)


event CollateralAdded:
    account: indexed(address)
    asset: indexed(address)
    amount: uint256


event CollateralWithdrawn:
    account: indexed(address)
    asset: indexed(address)
    amount: uint256
    balance_after: uint256


event PasanakuCreated:
    token_id: indexed(uint256)
    asset: indexed(address)
    amount: uint256


event PasanakuJoined:
    token_id: indexed(uint256)
    account: indexed(address)
    participant_count: uint256


event PasanakuStarted:
    token_id: indexed(uint256)
    asset: address
    amount: uint256
    started_at: uint256


event PasanakuDeposited:
    account: indexed(address)
    token_id: indexed(uint256)
    index: uint256
    asset: address
    amount: uint256


event PasanakuTicked:
    token_id: indexed(uint256)
    tick_index: uint256
    recipient: indexed(address)
    asset: address
    amount: uint256
    updated_at: uint256


event PasanakuPenalties:
    token_id: indexed(uint256)
    tick_index: uint256
    owner: indexed(address)
    asset: address
    amount: uint256


event PasanakuEnded:
    token_id: indexed(uint256)
    asset: indexed(address)
    amount: uint256
    ended_at: uint256


struct Pasanaku:
    token_id: uint256
    asset: address
    amount: uint256
    participants: DynArray[address, _PARTICIPANT_COUNT]
    index: uint256
    started: uint256
    updated: uint256
    ended: uint256


_PARTICIPANT_COUNT: constant(uint256) = 9
_MISS_PENALTY_BPS: constant(uint256) = 5
_DAYS_40: constant(uint256) = 40 * 24 * 60 * 60
_SUPPORTED_ASSETS_COUNT: constant(uint256) = 4
_SUPPORTED_ASSETS: immutable(address[_SUPPORTED_ASSETS_COUNT])
_TOKEN_AMOUNT: constant(uint256) = 1
_BPS_PRECISION: constant(uint256) = 10000

_counter: uint256
_pasanakus: HashMap[uint256, Pasanaku]
_collateral: HashMap[address, HashMap[address, uint256]]
_collateral_in_use: HashMap[address, HashMap[address, uint256]]
_deposited_for_pasanaku: HashMap[uint256, HashMap[uint256, HashMap[address, bool]]]  # nosplit
_successful_obligated_deposits: HashMap[uint256, HashMap[address, uint256]]
_slash_from_in_use: HashMap[uint256, HashMap[address, uint256]]
_active_pasanaku_by_asset: HashMap[address, uint256]


@deploy
@payable
def __init__(supported_assets: address[_SUPPORTED_ASSETS_COUNT]):
    _SUPPORTED_ASSETS = supported_assets

    ow.__init__()
    ow2step.__init__()
    erc1155.__init__("https://pasanaku.fun/pasanaku/")


@external
@nonreentrant
def add_collateral(asset: address, amount: uint256):
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset
    assert amount > 0  # dev: invalid amount

    self._collateral[msg.sender][asset] += amount
    log CollateralAdded(
        account=msg.sender,
        asset=asset,
        amount=amount,
    )
    success: bool = extcall IERC20(asset).transferFrom(msg.sender, self, amount, default_return_value=True) # nosplit
    assert success  # dev: transferFrom failed


@external
@nonreentrant
def deposit_to_pasanaku(amount: uint256, token_id: uint256):
    assert amount > 0  # dev: invalid amount
    assert token_id < self._counter  # dev: invalid token id

    pasanaku: Pasanaku = self._pasanakus[token_id]
    round_idx: uint256 = pasanaku.index

    assert pasanaku.started != empty(uint256)  # dev: pasanaku not started
    assert pasanaku.ended == empty(uint256)  # dev: pasanaku ended
    assert msg.sender in pasanaku.participants  # dev: account not in pasanaku # nosplit
    assert msg.sender != pasanaku.participants[round_idx]  # dev: active participant cannot deposit # nosplit
    assert not self._deposited_for_pasanaku[token_id][round_idx][msg.sender]  # dev: account already deposited # nosplit
    assert amount == pasanaku.amount  # dev: invalid deposit amount

    self._deposited_for_pasanaku[token_id][round_idx][msg.sender] = True
    self._successful_obligated_deposits[token_id][msg.sender] += 1

    success: bool = extcall IERC20(pasanaku.asset).transferFrom(msg.sender, self, amount, default_return_value=True) # nosplit
    assert success  # dev: transferFrom failed

    log PasanakuDeposited(
        account=msg.sender,
        token_id=token_id,
        index=round_idx,
        asset=pasanaku.asset,
        amount=amount,
    )


@external
@nonreentrant
def withdraw_collateral(asset: address, amount: uint256):
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset
    assert amount > 0  # dev: invalid amount

    collateral: uint256 = self._collateral[msg.sender][asset]
    collateral_in_use: uint256 = self._collateral_in_use[msg.sender][asset]
    assert collateral > collateral_in_use  # dev: collateral in use
    assert collateral - collateral_in_use >= amount  # dev: insufficient free collateral # nosplit

    self._collateral[msg.sender][asset] -= amount

    success: bool = extcall IERC20(asset).transfer(msg.sender, amount, default_return_value=True) # nosplit
    assert success  # dev: transfer failed

    log CollateralWithdrawn(
        account=msg.sender,
        asset=asset,
        amount=amount,
        balance_after=self._collateral[msg.sender][asset],
    )


@external
def create_pasanaku(asset: address, amount: uint256) -> uint256:
    assert amount > 0  # dev: invalid amount
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset

    token_id: uint256 = self._counter
    self._counter += 1

    pasanaku: Pasanaku = empty(Pasanaku)
    pasanaku.asset = asset
    pasanaku.amount = amount
    pasanaku.participants.append(msg.sender)
    self._pasanakus[token_id] = pasanaku
    self._update_collateral_in_use(pasanaku)

    log PasanakuCreated(
        token_id=token_id,
        asset=asset,
        amount=amount,
    )
    return token_id


@external
@nonreentrant
def join_pasanaku(token_id: uint256):
    assert token_id < self._counter  # dev: invalid token id

    pasanaku: Pasanaku = self._pasanakus[token_id]
    assert msg.sender not in pasanaku.participants  # dev: participant already joined # nosplit

    pasanaku.participants.append(msg.sender)
    self._update_collateral_in_use(pasanaku)
    self._pasanakus[token_id] = pasanaku

    log PasanakuJoined(
        token_id=token_id,
        account=msg.sender,
        participant_count=len(pasanaku.participants),
    )

    if len(pasanaku.participants) == _PARTICIPANT_COUNT:
        self._start_pasanaku(token_id)


@external
@nonreentrant
def tick(token_id: uint256):
    pasanaku: Pasanaku = self._pasanakus[token_id]
    assert pasanaku.started != empty(uint256)  # dev: pasanaku not started
    assert pasanaku.ended == empty(uint256)  # dev: pasanaku ended
    assert pasanaku.updated + _DAYS_40 <= block.timestamp  # dev: not enough time passed # nosplit

    round_idx: uint256 = pasanaku.index
    recipient: address = pasanaku.participants[round_idx]
    asset: address = pasanaku.asset

    recipient_payout: uint256 = empty(uint256)
    penalties: uint256 = empty(uint256)
    recipient_payout, penalties = self._settle_round(
        token_id, round_idx, recipient
    )

    pasanaku.updated = block.timestamp

    self._payout_recipient(token_id, pasanaku, recipient, recipient_payout)
    self._distribute_penalties(token_id, round_idx, penalties, pasanaku)

    log PasanakuTicked(
        token_id=token_id,
        tick_index=round_idx,
        recipient=recipient,
        asset=asset,
        amount=recipient_payout,
        updated_at=block.timestamp,
    )

    pasanaku.index += 1

    # Ending pasakanu if round index is the last one
    if round_idx == _PARTICIPANT_COUNT - 1:
        pasanaku.ended = block.timestamp
        self._unlock_collateral_in_use(token_id, pasanaku)
        log PasanakuEnded(
            token_id=token_id,
            asset=pasanaku.asset,
            amount=pasanaku.amount,
            ended_at=block.timestamp,
        )
        self._active_pasanaku_by_asset[asset] -= 1

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
def uri(token_id: uint256) -> String[512]:
    if token_id >= self._counter:
        return "https://pasanaku.fun/pasanaku/not-created"
    
    pasanaku: Pasanaku = self._pasanakus[token_id]
    if pasanaku.ended != empty(uint256):
        return "https://pasanaku.fun/pasanaku/ended"
    
    if pasanaku.started != empty(uint256):
        return "https://pasanaku.fun/pasanaku/ongoing"
    
    return "https://pasanaku.fun/pasanaku/pending"


@external
@view
def isApprovedForAll(owner: address, operator: address) -> bool:
    return False


@external
@view
def pasanaku(pasanaku_id: uint256) -> Pasanaku:
    return self._pasanakus[pasanaku_id]


@external
@view
def collateral_in_use(participant: address, asset: address) -> uint256:
    return self._collateral_in_use[participant][asset]


@external
@view
def deposited_for_pasanaku(
    pasanaku_id: uint256, index: uint256, participant: address
) -> bool:
    return self._deposited_for_pasanaku[pasanaku_id][index][participant]  # nosplit


@external
@view
def successful_obligated_deposits(
    token_id: uint256, participant: address
) -> uint256:
    return self._successful_obligated_deposits[token_id][participant]


@external
@view
def active_pasanaku_for_asset(asset: address) -> uint256:
    return self._active_pasanaku_by_asset[asset]


@external
@view
def participant_count() -> uint256:
    return _PARTICIPANT_COUNT


@external
@view
def supported_assets() -> address[_SUPPORTED_ASSETS_COUNT]:
    return _SUPPORTED_ASSETS


@external
@view
def collateral(participant: address, asset: address) -> uint256:
    return self._collateral[participant][asset]


@external
@view
def free_collateral(participant: address, asset: address) -> uint256:
    collateral: uint256 = self._collateral[participant][asset]
    in_use: uint256 = self._collateral_in_use[participant][asset]
    if collateral <= in_use:
        return 0

    return collateral - in_use


@external
@pure
def pledge(amount: uint256) -> uint256:
    return self._pledge(amount)


@internal
def _update_collateral_in_use(pasanaku: Pasanaku):
    lock_amt: uint256 = self._pledge(pasanaku.amount)
    assert self._collateral[msg.sender][pasanaku.asset] >= lock_amt  # dev: insufficient collateral # nosplit

    collateral: uint256 = self._collateral[msg.sender][pasanaku.asset]
    in_use: uint256 = self._collateral_in_use[msg.sender][pasanaku.asset]
    assert collateral - in_use >= lock_amt  # dev: collateral already pledged # nosplit
    self._collateral_in_use[msg.sender][pasanaku.asset] += lock_amt


@internal
def _start_pasanaku(token_id: uint256):
    pasanaku: Pasanaku = self._pasanakus[token_id]
    assert pasanaku.asset != empty(address)  # dev: pasanaku not created

    pasanaku.token_id = token_id
    pasanaku.started = block.timestamp
    pasanaku.updated = block.timestamp

    self._pasanakus[token_id] = pasanaku
    self._active_pasanaku_by_asset[pasanaku.asset] += 1

    for p: address in pasanaku.participants:
        erc1155._safe_mint(p, token_id, _TOKEN_AMOUNT, b"")

    log PasanakuStarted(
        token_id=token_id,
        asset=pasanaku.asset,
        amount=pasanaku.amount,
        started_at=block.timestamp,
    )


@internal
def _payout_recipient(
    token_id: uint256,
    pasanaku: Pasanaku,
    recipient: address,
    payout: uint256,
):
    if payout == 0:
        return
    asset: IERC20 = IERC20(pasanaku.asset)
    success: bool = extcall asset.transfer(recipient, payout, default_return_value=True) # nosplit
    assert success  # dev: transfer failed


@internal
def _unlock_collateral_in_use(token_id: uint256, pasanaku: Pasanaku):
    assert pasanaku.ended != empty(uint256)  # dev: pasanaku not ended
    pledge_amt: uint256 = self._pledge(pasanaku.amount)
    for participant: address in pasanaku.participants:
        slashed: uint256 = self._slash_from_in_use[token_id][participant]
        self._collateral_in_use[participant][pasanaku.asset] -= (
            pledge_amt - slashed
        )


@internal
def _settle_round(
    token_id: uint256, round_idx: uint256, recipient: address
) -> (uint256, uint256):
    pasanaku: Pasanaku = self._pasanakus[token_id]
    asset: address = pasanaku.asset
    amt: uint256 = pasanaku.amount
    penalty_per: uint256 = amt * _MISS_PENALTY_BPS // _BPS_PRECISION

    recipient_payout: uint256 = 0
    penalties: uint256 = 0

    for p: address in pasanaku.participants:
        if p == recipient:
            continue
        elif self._deposited_for_pasanaku[token_id][round_idx][p]:
            recipient_payout += amt
        else:
            slash_total: uint256 = amt + penalty_per
            assert self._collateral[p][asset] >= slash_total  # dev: insufficient collateral for slash # nosplit
            self._collateral[p][asset] -= slash_total
            self._collateral_in_use[p][asset] -= slash_total
            self._slash_from_in_use[token_id][p] += slash_total
            recipient_payout += amt
            penalties += penalty_per
    
    return recipient_payout, penalties


@internal
def _distribute_penalties(
    token_id: uint256,
    round_idx: uint256,
    penalty_pool: uint256,
    pasanaku: Pasanaku,
):
    if penalty_pool == 0:
        return

    asset: address = pasanaku.asset
    fee_sink: address = ow.owner
    extcall IERC20(asset).transfer(fee_sink, penalty_pool)
    log PasanakuPenalties(
        token_id=token_id,
        tick_index=round_idx,
        owner=fee_sink,
        asset=asset,
        amount=penalty_pool,
    )


@internal
@pure
def _pledge(amount: uint256) -> uint256:
    total_amount: uint256 = amount * _PARTICIPANT_COUNT
    total_penalties: uint256 = total_amount * _MISS_PENALTY_BPS // _BPS_PRECISION
    return total_amount + total_penalties
