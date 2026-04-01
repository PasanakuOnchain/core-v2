# pragma version ==0.4.3
# pragma nonreentrancy off

# NOTE: Updating the signature, removing min and max participants

from ethereum.ercs import IERC20

count: public(uint256)


@external
def increment():
    self.count += 1


@external
def decrement():
    self.count -= 1


@external
def reset():
    self.count = 0


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
    tokenId: indexed(uint256)
    creator: indexed(address)


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
    assert amount > 0, "pasanaku: invalid amount"
    assert asset in _supported_assets, "pasanaku: unsupported asset"
    assert msg.value > PROTOCOL_FEE, "pasanaku: insufficient fee"

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


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                      INTERNAL FUNCTIONS                      #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

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
