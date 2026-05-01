# pragma version ==0.4.3
# pragma nonreentrancy off

from ethereum.ercs import IERC20


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


event PasanakuEnded:
    token_id: indexed(uint256)
    asset: indexed(address)
    amount: uint256
    ended_at: uint256


struct Pasanaku:
    token_id: uint256
    asset: address
    amount: uint256
    participants: DynArray[address, 12]
    index: uint256
    started: uint256
    updated: uint256
    ended: uint256


_PARTICIPANT_COUNT: constant(uint256) = 9
_TOKEN_MINT_AMOUNT: constant(uint256) = 1
_TOKEN_ID_OFFSET: constant(uint256) = 1
_DAYS_40: constant(uint256) = 40 * 24 * 60 * 60
_SUPPORTED_ASSETS_COUNT: constant(uint256) = 3
_SUPPORTED_ASSETS: immutable(address[_SUPPORTED_ASSETS_COUNT])

_counter: uint256
_pasanakus: HashMap[uint256, Pasanaku]
_collateral: HashMap[address, HashMap[address, uint256]]
_collateral_in_use: HashMap[address, HashMap[address, uint256]]
_deposited_for_pasanaku: HashMap[uint256, HashMap[uint256, HashMap[address, bool]]]  # nosplit


@deploy
@payable
def __init__(supported_assets: address[_SUPPORTED_ASSETS_COUNT]):
    _SUPPORTED_ASSETS = supported_assets


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
    extcall IERC20(asset).transferFrom(msg.sender, self, amount)


@external
def deposit_to_pasanaku(asset: address, amount: uint256, token_id: uint256):
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset
    assert amount > 0  # dev: invalid amount
    assert token_id >= _TOKEN_ID_OFFSET  # dev: invalid token id

    pasanaku: Pasanaku = self._pasanakus[token_id]
    index: uint256 = pasanaku.index

    assert pasanaku.started != empty(uint256)  # dev: pasanaku not started
    assert pasanaku.ended == empty(uint256)  # dev: pasanaku ended
    assert msg.sender in pasanaku.participants  # dev: account not in pasanaku # nosplit
    assert msg.sender != pasanaku.participants[index]  # dev: active participant cannot deposit # nosplit
    assert not self._deposited_for_pasanaku[token_id][index][msg.sender]  # dev: account already deposited # nosplit
    assert amount == pasanaku.amount  # dev: invalid deposit amount

    self._deposited_for_pasanaku[token_id][index][msg.sender] = True

    log PasanakuDeposited(
        account=msg.sender,
        token_id=token_id,
        index=index,
        asset=asset,
        amount=amount,
    )
    extcall IERC20(asset).transferFrom(msg.sender, self, amount)


@external
@nonreentrant
def withdraw_collateral(asset: address, amount: uint256):
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset
    assert amount > 0  # dev: invalid amount

    collateral: uint256 = self._collateral[msg.sender][asset]
    collateral_in_use: uint256 = self._collateral_in_use[msg.sender][asset]
    assert collateral > collateral_in_use  # dev: collateral in use
    assert collateral - collateral_in_use >= amount # dev: insufficient collateral # nosplit

    self._collateral[msg.sender][asset] -= amount
    extcall IERC20(asset).transfer(msg.sender, amount)

    log CollateralWithdrawn(
        account=msg.sender,
        asset=asset,
        amount=amount,
        balance_after=self._collateral[msg.sender][asset],
    )


@external
def create_pasanaku(asset: address, amount: uint256) -> uint256:
    assert asset in _SUPPORTED_ASSETS  # dev: unsupported asset

    token_id: uint256 = self._counter
    self._counter += 1

    pasanaku: Pasanaku = empty(Pasanaku)
    pasanaku.asset = asset
    pasanaku.amount = amount
    pasanaku.participants.append(msg.sender)
    self._update_collateral_in_use(pasanaku)
    self._pasanakus[token_id] = pasanaku

    log PasanakuCreated(
        token_id=token_id,
        asset=asset,
        amount=amount,
    )
    return token_id


@external
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

    index: uint256 = pasanaku.index
    pasanaku.index += 1

    participant: address = pasanaku.participants[index]
    pasanaku.updated = block.timestamp

    if index == _PARTICIPANT_COUNT - 1:
        pasanaku.ended = block.timestamp
        self._unlock_collateral_in_use(token_id, pasanaku)
        log PasanakuEnded(
            token_id=token_id,
            asset=pasanaku.asset,
            amount=pasanaku.amount,
            ended_at=block.timestamp,
        )
    else:
        log PasanakuTicked(
            token_id=token_id,
            tick_index=index,
            recipient=participant,
            asset=pasanaku.asset,
            amount=pasanaku.amount,
            updated_at=block.timestamp,
        )

    self._pasanakus[token_id] = pasanaku

    amount: uint256 = self._update_collateral(token_id)
    extcall IERC20(pasanaku.asset).transfer(participant, amount)


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
    pasanaku: Pasanaku = self._pasanakus[token_id]

    if pasanaku.ended != empty(uint256):
        return "https://pasanaku.fun/pasanaku/ended"
    elif pasanaku.started != empty(uint256):
        return "https://pasanaku.fun/pasanaku/ongoing"
    elif token_id < self._counter:
        return "https://pasanaku.fun/pasanaku/pending"
    else:
        return "https://pasanaku.fun/pasanaku/not-created"


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
def _update_collateral_in_use(pasanaku: Pasanaku):
    pasanaku_amount: uint256 = pasanaku.amount * _PARTICIPANT_COUNT
    assert self._collateral[msg.sender][pasanaku.asset] >= pasanaku_amount  # dev: insufficient collateral # nosplit

    collateral: uint256 = self._collateral[msg.sender][pasanaku.asset]
    in_use: uint256 = self._collateral_in_use[msg.sender][pasanaku.asset]
    assert collateral - in_use >= pasanaku_amount  # dev: collateral already pledged # nosplit
    self._collateral_in_use[msg.sender][pasanaku.asset] += pasanaku_amount


@internal
def _start_pasanaku(token_id: uint256):
    pasanaku: Pasanaku = self._pasanakus[token_id]
    assert pasanaku.asset != empty(address)  # dev: pasanaku not created

    # Update pasanaku
    pasanaku.token_id = token_id
    pasanaku.started = block.timestamp
    pasanaku.updated = block.timestamp

    # Update pasanaku storage
    self._pasanakus[token_id] = pasanaku

    # Mint tokens
    # TODO: mint tokens

    log PasanakuStarted(
        token_id=token_id,
        asset=pasanaku.asset,
        amount=pasanaku.amount,
        started_at=block.timestamp,
    )


@internal
def _unlock_collateral_in_use(token_id: uint256, pasanaku: Pasanaku):
    for participant: address in pasanaku.participants:
        for index: uint256 in range(pasanaku.index-1, bound=_PARTICIPANT_COUNT):
            if self._deposited_for_pasanaku[token_id][index][participant]:
                self._collateral_in_use[participant][pasanaku.asset] -= pasanaku.amount


@internal
def _update_collateral(token_id: uint256) -> uint256:
    pasanaku: Pasanaku = self._pasanakus[token_id]
    index: uint256 = pasanaku.index

    amount: uint256 = 0
    for p: address in pasanaku.participants:
        if not self._deposited_for_pasanaku[token_id][index][p]:
            self._collateral[p][pasanaku.asset] -= pasanaku.amount
            self._collateral_in_use[p][pasanaku.asset] -= pasanaku.amount
        amount += pasanaku.amount

    return amount


@internal
@view
def _amount_deposited_for_tick(token_id: uint256, index: uint256) -> uint256:
    pasanaku: Pasanaku = self._pasanakus[token_id]
    total: uint256 = 0
    for p: address in pasanaku.participants:
        if not self._deposited_for_pasanaku[token_id][index][p]:
            total += pasanaku.amount
    return total
