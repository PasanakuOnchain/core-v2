# pragma version ==0.4.3
# pragma nonreentrancy off

from ethereum.ercs import IERC20


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                          CONSTANTS                           #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

PROTOCOL_FEE: constant(uint256) = as_wei_value(0.000075, "ether")
TOKEN_AMOUNT: constant(uint256) = 1
PARTICIPANTS_COUNT: constant(uint256) = 12
CLAIM_GRACE_PERIOD: constant(uint256) = 10 * 24 * 60 * 60  # 10 days
SUPPORTED_ASSETS_COUNT: constant(uint256) = 10
MIN_LOBBY_DEADLINE: constant(uint256) = 1 * 24 * 60 * 60  # 1 day
MAX_START_DATE: constant(uint256) = 35 * 24 * 60 * 60  # 35 days


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                            EVENTS                            #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

event LobbyCreated:
    asset: indexed(address)
    amount: uint256
    tokenId: indexed(uint256)
    creator: indexed(address)
    createdAt: uint256


event LobbyFinalized:
    tokenId: indexed(uint256)
    participants: DynArray[address, PARTICIPANTS_COUNT]
    finalizedAt: uint256


event LobbyCancelled:
    creator: indexed(address)
    tokenId: indexed(uint256)


event Joined:
    account: indexed(address)
    tokenId: indexed(uint256)


event LeftLobby:
    account: indexed(address)
    tokenId: indexed(uint256)


event CollateralAdded:
    account: indexed(address)
    asset: indexed(address)
    amount: uint256


event CollateralRemoved:
    account: indexed(address)
    asset: indexed(address)
    amount: uint256


event Deposited:
    participant: indexed(address)
    tokenId: indexed(uint256)
    index: uint256
    amount: uint256
    totalDeposited: uint256


event Claimed:
    participant: indexed(address)
    tokenId: indexed(uint256)
    index: uint256
    amount: uint256
    totalDeposited: uint256


event Skipped:
    destination: indexed(address)
    tokenId: indexed(uint256)
    index: uint256
    amount: uint256


event Ended:
    tokenId: indexed(uint256)
    lastUpdatedAt: uint256


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                           STRUCTS                            #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

struct RotatingSavings:
    participants: DynArray[address, PARTICIPANTS_COUNT]
    asset: address
    amount: uint256
    currentIndex: uint256
    totalDeposited: uint256
    tokenId: uint256
    ended: bool
    started: bool
    cancelled: bool
    creator: address
    createdAt: uint256
    lastUpdatedAt: uint256


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                           STORAGE                            #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

# @dev
_rotating_savings: HashMap[uint256, RotatingSavings]

# @dev
_deposited: HashMap[address, HashMap[uint256, bool]]

# @dev
_free_collateral: HashMap[address, HashMap[address, uint256]]

# @dev
_locked_collateral: HashMap[address, HashMap[uint256, uint256]]

# @dev
_collateral_reserves: HashMap[address, uint256]

# @dev TODO: Where is this used?
_active_round_pools: HashMap[address, uint256]

# dev
_supported_assets: immutable(address[SUPPORTED_ASSETS_COUNT])

# dev
_counter: uint256

# @dev
_owner: address

#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                          INITIALIZER                         #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#
@deploy
def __init__(supported_assets: address[SUPPORTED_ASSETS_COUNT]):
    _supported_assets = supported_assets


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                     EXTERNAL FUNCTIONS                       #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

@external
@nonreentrant
def addCollateral(asset: address, amount: uint256):
    assert amount > 0, "pasanaku: invalid amount"
    assert asset in _supported_assets, "pasanaku: unsupported asset"

    self._safeTransferFrom(msg.sender, self, asset, amount)
    self._free_collateral[msg.sender][asset] += amount
    self._collateral_reserves[asset] += amount

    log CollateralAdded(account=msg.sender, asset=asset, amount=amount)


@external
@nonreentrant
def removeCollateral(asset: address, amount: uint256):
    assert amount > 0, "pasanaku: invalid amount"
    assert asset in _supported_assets, "pasanaku: unsupported asset"
    assert (
        self._free_collateral[msg.sender][asset] >= amount
    ), "pasanaku: insufficient free collateral"
    assert (
        self._collateral_reserves[asset] >= amount
    ), "pasanaku: insufficient collateral reserves"

    self._safeTransfer(msg.sender, asset, amount)
    self._free_collateral[msg.sender][asset] -= amount
    self._collateral_reserves[asset] -= amount

    log CollateralRemoved(account=msg.sender, asset=asset, amount=amount)


@external
@payable
@nonreentrant
def create(asset: address, amount: uint256) -> uint256:
    assert msg.value >= PROTOCOL_FEE, "pasanaku: insufficient fee"
    assert amount > 0, "pasanaku: invalid amount"
    assert asset in _supported_assets, "pasanaku: unsupported asset"

    token_id: uint256 = self._counter
    self._counter += 1

    timestamp: uint256 = block.timestamp
    self._rotating_savings[token_id] = RotatingSavings(
        participants=empty(DynArray[address, PARTICIPANTS_COUNT]),
        asset=asset,
        amount=amount,
        currentIndex=empty(uint256),
        totalDeposited=empty(uint256),
        tokenId=token_id,
        ended=empty(bool),
        started=empty(bool),
        cancelled=empty(bool),
        creator=msg.sender,
        createdAt=timestamp,
        lastUpdatedAt=timestamp,
    )
    log LobbyCreated(
        asset=asset,
        amount=amount,
        tokenId=token_id,
        creator=msg.sender,
        createdAt=timestamp,
    )
    return token_id


@external
@payable
@nonreentrant
def join(token_id: uint256):
    assert msg.value >= PROTOCOL_FEE, "pasanaku: insufficient fee"
    assert token_id <= self._counter, "pasanaku: invalid token id"

    rs: RotatingSavings = self._rotating_savings[token_id]
    assert not rs.cancelled, "pasanaku: lobby cancelled"
    assert not rs.started, "pasanaku: lobby already starded"
    assert msg.sender not in rs.participants, "pasanaku: caller already joined"
    assert len(rs.participants) < PARTICIPANTS_COUNT, "pasanaku: lobby full"
    assert (
        self._free_collateral[msg.sender][rs.asset] < rs.amount
    ), "pasanaku: insufficient collateral"

    self._free_collateral[msg.sender][rs.asset] -= rs.amount
    self._locked_collateral[msg.sender][token_id] += rs.amount
    self._rotating_savings[token_id].participants.append(msg.sender)
    # TODO: IMplement ERC1155 mint
    log Joined(account=msg.sender, tokenId=token_id)


@external
@payable
@nonreentrant
def leaveLobby(token_id: uint256):
    assert msg.value >= PROTOCOL_FEE, "pasanaku: insufficient fee"
    assert token_id <= self._counter, "pasanaku: invalid token id"
    rs: RotatingSavings = self._rotating_savings[token_id]
    assert not rs.cancelled, "pasanaku: lobby cancelled"
    assert not rs.started, "pasanaku: lobby already starded"
    assert msg.sender in rs.participants, "pasanaku: caller cannot leave lobby"

    self._removeParticipant(token_id, msg.sender)
    log LeftLobby(account=msg.sender, tokenId=token_id)


@external
@payable
@nonreentrant
def cancelLobby(token_id: uint256):
    assert msg.value > PROTOCOL_FEE, "pasanaku: insufficient fee"
    assert token_id <= self._counter, "pasanaku: invalid token id"
    rs: RotatingSavings = self._rotating_savings[token_id]
    assert not rs.started, "pasanaku: already started"
    assert not rs.cancelled, "pasanaku: already cancelled"
    assert rs.creator == msg.sender, "pasanku: cannot cancel lobby"

    for participant: address in rs.participants:
        self._locked_collateral[participant][token_id] = 0
        self._free_collateral[participant][rs.asset] += rs.amount
        # TODO: burn ERC1155
    self._rotating_savings[token_id].cancelled = True
    log LobbyCancelled(creator=msg.sender, tokenId=token_id)


@external
@nonreentrant
def finalizeLobby(token_id: uint256):
    assert token_id <= self._counter, "pasanaku: invalid token id"
    rs: RotatingSavings = self._rotating_savings[token_id]
    assert not rs.started, "pasanaku: already started"
    assert not rs.cancelled, "pasanaku: already cancelled"
    assert (
        len(rs.participants) == PARTICIPANTS_COUNT
    ), "pasanaku: insufficient participants"

    self._shuffleParticipants(token_id)

    self._rotating_savings[token_id].started = True
    self._rotating_savings[token_id].lastUpdatedAt = block.timestamp
    log LobbyFinalized(
        tokenId=token_id,
        participants=rs.participants,
        finalizedAt=block.timestamp,
    )


@external
@payable
@nonreentrant
def deposit(token_id: uint256) -> bool:
    assert msg.value >= PROTOCOL_FEE, "pasanaku: insufficient fee"
    assert token_id <= self._counter, "pasanaku: invalid token id"
    assert self._canDeposit(msg.sender, token_id), "pasanaku: cannot deposit"

    rs: RotatingSavings = self._rotating_savings[token_id]
    self._rotating_savings[token_id].lastUpdatedAt = block.timestamp
    self._rotating_savings[token_id].totalDeposited += rs.amount
    self._deposited[msg.sender][token_id] = True
    self._active_round_pools[rs.asset] += rs.amount

    self._safeTransferFrom(msg.sender, self, rs.asset, rs.amount)

    log Deposited(
        participant=msg.sender,
        tokenId=token_id,
        index=rs.currentIndex,
        amount=rs.amount,
        totalDeposited=rs.totalDeposited + rs.amount,
    )
    return True


@external
@payable
@nonreentrant
def claim(token_id: uint256) -> bool:
    assert msg.value >= PROTOCOL_FEE, "pasanaku: insufficient fee"
    assert token_id <= self._counter, "pasanaku: invalid token id"
    assert self._canClaim(msg.sender, token_id), "pasanaku: cannot claim"

    rs: RotatingSavings = self._rotating_savings[token_id]
    beneficiary: address = rs.participants[rs.currentIndex]

    self._applyRound(rs, beneficiary, True)
    return True


@external
@payable
@nonreentrant
def skip(token_id: uint256, destination: address) -> bool:
    assert msg.value >= PROTOCOL_FEE, "pasanaku: insufficient fee"
    assert token_id <= self._counter, "pasanaku: invalid token id"
    assert self._canClaim(msg.sender, token_id), "pasanaku: cannot claim"

    rs: RotatingSavings = self._rotating_savings[token_id]
    self._applyRound(rs, destination, False)
    return True


@external
def collectProtocolFees():
    send(self._owner, self.balance)


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                      INTERNAL FUNCTIONS                      #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

@internal
@view
def _canDeposit(participant: address, token_id: uint256) -> bool:
    rs: RotatingSavings = self._rotating_savings[token_id]
    return (
        not rs.ended
        and not rs.cancelled
        and rs.started
        and participant in rs.participants
        and participant != rs.participants[rs.currentIndex]
        and not self._deposited[participant][token_id]
    )


@internal
@view
def _canClaim(participant: address, token_id: uint256) -> bool:
    rs: RotatingSavings = self._rotating_savings[token_id]
    return (
        not rs.ended
        and not rs.cancelled
        and rs.started
        and participant in rs.participants
        and participant == rs.participants[rs.currentIndex]
        and block.timestamp - rs.lastUpdatedAt < CLAIM_GRACE_PERIOD
    )


@internal
def _applyRound(rs: RotatingSavings, destination: address, is_claim: bool):
    amount_to_pay: uint256 = rs.totalDeposited
    current_index: uint256 = rs.currentIndex
    asset: address = rs.asset
    assert self._collateral_reserves[asset] >= amount_to_pay, "pasanaku: insufficient free collateral"

    self._active_round_pools[asset] -= amount_to_pay
    self._rotating_savings[rs.tokenId].lastUpdatedAt = block.timestamp
    self._rotating_savings[rs.tokenId].currentIndex = rs.currentIndex + 1
    self._rotating_savings[rs.tokenId].totalDeposited = 0
    self._rotating_savings[rs.tokenId].ended = rs.currentIndex + 1 >= len(
        rs.participants
    )

    self._safeTransfer(destination, asset, amount_to_pay)
    if rs.ended:
        for participant: address in rs.participants:
            self._locked_collateral[participant][rs.tokenId] -= rs.amount
            self._free_collateral[participant][rs.asset] += rs.amount
        log Ended(tokenId=rs.tokenId, lastUpdatedAt=block.timestamp)

    if is_claim:
        log Claimed(
            participant=destination,
            tokenId=rs.tokenId,
            index=rs.currentIndex,
            amount=amount_to_pay,
            totalDeposited=rs.totalDeposited,
        )
    else:
        log Skipped(
            destination=destination,
            tokenId=rs.tokenId,
            index=rs.currentIndex,
            amount=amount_to_pay,
        )


@internal
def _removeParticipant(token_id: uint256, participant: address):
    rs: RotatingSavings = self._rotating_savings[token_id]
    idx: uint256 = len(rs.participants) - 1
    last_participant: address = rs.participants[idx]
    for i: uint256 in range(len(rs.participants), bound=PARTICIPANTS_COUNT):
        if rs.participants[i] == participant:
            self._rotating_savings[token_id].participants[i] = last_participant
    self._rotating_savings[token_id].participants.pop()


@internal
def _shuffleParticipants(token_id: uint256):
    pass


@internal
def _safeTransferFrom(
    _from: address, _to: address, asset: address, amount: uint256
):
    initial: uint256 = staticcall IERC20(asset).balanceOf(_to)
    extcall IERC20(asset).transferFrom(_from, _to, amount)
    ending: uint256 = staticcall IERC20(asset).balanceOf(_to)
    assert initial - amount == ending, "pasanku: transferFrom failed"


@internal
def _safeTransfer(_to: address, asset: address, amount: uint256):
    initial: uint256 = staticcall IERC20(asset).balanceOf(_to)
    extcall IERC20(asset).transfer(_to, amount)
    ending: uint256 = staticcall IERC20(asset).balanceOf(_to)
    assert initial - amount == ending, "pasanku: transfer failed"
