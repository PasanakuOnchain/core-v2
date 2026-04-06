# pragma version ==0.4.3
# pragma nonreentrancy on
"""
@title `Pasanaku` - Rotating savings decentralized protocol
@custom:contract-name Pasanaku
@license GNU Affero General Public License v3.0 only
@author Rafael Abuawad <x.com/rabuawad_>
@notice This code is for testing purposes only, is not production ready and is not audited.
        Everything is subject to change. Use at your own__interface__ risk.
@custom:security-contact https://x.com/rabuawad_
"""

#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                           IMPORTS                            #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

from ethereum.ercs import IERC165
implements: IERC165

from snekmate.tokens.interfaces import IERC1155
implements: IERC1155

from snekmate.auth import ownable as ow
initializes: ow

from snekmate.tokens import erc1155
initializes: erc1155[ownable := ow]

from ethereum.ercs import IERC20

#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                           MODULES                            #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

exports: (
    erc1155.owner,
    erc1155.supportsInterface,
    erc1155.balanceOfBatch,
    erc1155.exists,
    erc1155.balanceOf,
    erc1155.total_supply,
)


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                          CONSTANTS                           #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

PROTOCOL_FEE: constant(uint256) = as_wei_value(0.000075, "ether")
MINT_TOKEN_AMOUNT: constant(uint256) = 1
PARTICIPANTS_COUNT: constant(uint256) = 12
CLAIM_GRACE_PERIOD: constant(uint256) = 10 * 24 * 60 * 60  # 10 days
SUPPORTED_ASSETS_COUNT: constant(uint256) = 3
MIN_LOBBY_DEADLINE: constant(uint256) = 1 * 24 * 60 * 60  # 1 day
MAX_START_DATE: constant(uint256) = 35 * 24 * 60 * 60  # 35 days


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                            EVENTS                            #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

event LobbyCreated:
    asset: indexed(address)
    tokenId: indexed(uint256)
    amount: uint256


event LobbyFinalized:
    tokenId: indexed(uint256)


event JoinedLobby:
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


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                           STORAGE                            #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

# @dev Lobby / round state keyed by ERC-1155 token id.
_rotating_savings: HashMap[uint256, RotatingSavings]

# @dev Whether a participant has deposited for the current round (per token id).
_deposited: HashMap[address, HashMap[uint256, bool]]

# @dev User collateral not locked in a lobby, per asset.
_free_collateral: HashMap[address, HashMap[address, uint256]]

# @dev Collateral locked while in a lobby, per user and token id.
_locked_collateral: HashMap[address, HashMap[uint256, uint256]]

# @dev Total collateral held by the protocol per asset.
_collateral_reserves: HashMap[address, uint256]

# @dev Whitelisted ERC-20 assets set at deploy.
_supported_assets: immutable(address[SUPPORTED_ASSETS_COUNT])

# @dev Next token id; monotonically increases on `create`.
_counter: uint256

#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                          INITIALIZER                         #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#
@deploy
def __init__(supported_assets: address[SUPPORTED_ASSETS_COUNT]):
    ow.__init__()
    erc1155.__init__("")
    _supported_assets = supported_assets


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                     EXTERNAL FUNCTIONS                       #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

@external
def addCollateral(asset: address, amount: uint256):
    assert amount > 0, "pasanaku: invalid amount"
    assert asset in _supported_assets, "pasanaku: unsupported asset"

    self._safeTransferFrom(msg.sender, self, asset, amount)
    self._free_collateral[msg.sender][asset] += amount
    self._collateral_reserves[asset] += amount

    log CollateralAdded(account=msg.sender, asset=asset, amount=amount)


@external
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
    )
    log LobbyCreated(
        asset=asset,
        tokenId=token_id,
        amount=amount,
    )
    return token_id


@external
@payable
def join(token_id: uint256):
    assert msg.value >= PROTOCOL_FEE, "pasanaku: insufficient fee"
    assert token_id <= self._counter, "pasanaku: invalid token id"

    rs: RotatingSavings = self._rotating_savings[token_id]
    assert not rs.started, "pasanaku: lobby already starded"
    assert msg.sender not in rs.participants, "pasanaku: caller already joined"

    free_collateral: uint256 = self._free_collateral[msg.sender][rs.asset]
    assert free_collateral >= rs.amount, "pasanaku: insufficient collateral"

    amount_to_pay: uint256 = rs.amount * (len(rs.participants) - 1)
    self._free_collateral[msg.sender][rs.asset] -= amount_to_pay
    self._locked_collateral[msg.sender][token_id] += amount_to_pay
    self._rotating_savings[token_id].participants.append(msg.sender)

    log JoinedLobby(account=msg.sender, tokenId=token_id)


@external
def finalizeLobby(token_id: uint256):
    assert token_id <= self._counter, "pasanaku: invalid token id"
    rs: RotatingSavings = self._rotating_savings[token_id]
    assert not rs.started, "pasanaku: already started"

    length: uint256 = len(rs.participants)
    assert length == PARTICIPANTS_COUNT, "pasanaku: insufficient participants"
    assert msg.sender in rs.participants, "pasanaku: caller not a participant"

    self._shuffleParticipants(token_id)
    self._rotating_savings[token_id].started = True

    for participant: address in rs.participants:
        self._mint(participant, token_id)

    log LobbyFinalized(
        tokenId=token_id,
    )


@external
@payable
def deposit(token_id: uint256) -> bool:
    assert token_id <= self._counter, "pasanaku: invalid token id"
    assert self._canDeposit(msg.sender, token_id), "pasanaku: cannot deposit"

    rs: RotatingSavings = self._rotating_savings[token_id]
    self._rotating_savings[token_id].totalDeposited += rs.amount
    self._deposited[msg.sender][token_id] = True
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
def claim(token_id: uint256) -> bool:
    assert msg.value >= PROTOCOL_FEE, "pasanaku: insufficient fee"
    assert token_id <= self._counter, "pasanaku: invalid token id"
    assert self._canClaim(msg.sender, token_id), "pasanaku: cannot claim"

    self._applyRound(token_id, True)
    return True


@external
@payable
def skip(token_id: uint256) -> bool:
    assert msg.value >= PROTOCOL_FEE, "pasanaku: insufficient fee"
    assert token_id <= self._counter, "pasanaku: invalid token id"

    self._applyRound(token_id, False)
    return True


@external
def collectProtocolFees():
    send(ow.owner, self.balance)


@external
def skim(asset: address, amount: uint256):
    if asset in _supported_assets:
        balance: uint256 = staticcall IERC20(asset).balanceOf(self)
        reserves: uint256 = self._collateral_reserves[asset]
        diff: uint256 = balance - reserves
        assert diff >= amount, "pasanaku: insufficient difference"

    self._safeTransfer(ow.owner, asset, amount)


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


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                   EXTERNAL VIEW FUNCTIONS                    #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

@view
@external
def uri(id: uint256) -> String[512]:
    rs: RotatingSavings = self._rotating_savings[id]
    if rs.ended:
        return "https://pasanaku.fun/pasanaku/ended"
    elif rs.started:
        return "https://pasanaku.fun/pasanaku/started"
    else:
        return "https://pasanaku.fun/pasanaku/active"


@view
@external
def collateralReserves(asset: address) -> uint256:
    return self._collateral_reserves[asset]


@view
@external
def freeCollateral(account: address, asset: address) -> uint256:
    return self._free_collateral[account][asset]


@view
@external
def lockedCollateral(account: address, token_id: uint256) -> uint256:
    return self._locked_collateral[account][token_id]


@view
@external
def isApprovedForAll(arg0: address, arg1: address) -> bool:
    return False


@view
@external
def amountToPay(token_id: uint256) -> uint256:
    return self._amountToPay(token_id)


@external
@view
def protocolFee() -> uint256:
    return PROTOCOL_FEE


@external
@view
def supportedAssets() -> address[SUPPORTED_ASSETS_COUNT]:
    return _supported_assets


@external
@view
def rotatingSavings(token_id: uint256) -> RotatingSavings:
    return self._rotating_savings[token_id]


@external
@view
def canDeposit(participant: address, token_id: uint256) -> bool:
    return self._canDeposit(participant, token_id)


@external
@view
def canClaim(participant: address, token_id: uint256) -> bool:
    return self._canClaim(participant, token_id)


@external
@view
def canSkip(participant: address, token_id: uint256) -> bool:
    return self._canClaim(participant, token_id)


#*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*#
#                      INTERNAL FUNCTIONS                      #
#*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*#

@view
@internal
def _amountToPay(token_id: uint256) -> uint256:
    rs: RotatingSavings = self._rotating_savings[token_id]
    return rs.amount * (len(rs.participants) - 1)


@internal
@view
def _canDeposit(participant: address, token_id: uint256) -> bool:
    rs: RotatingSavings = self._rotating_savings[token_id]
    return (
        not rs.ended
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
        and rs.started
        and participant in rs.participants
        and participant == rs.participants[rs.currentIndex]
    )


@internal
def _applyRound(token_id: uint256, is_claim: bool):
    rs: RotatingSavings = self._rotating_savings[token_id]

    collateral_reserve: uint256 = self._collateral_reserves[rs.asset]
    assert collateral_reserve >= rs.amount

    total_deposited: uint256 = rs.totalDeposited
    amount_to_release: uint256 = rs.amount * (len(rs.participants) - 1)
    assert total_deposited >= amount_to_release

    # Transfer collateral
    destination: address = rs.participants[rs.currentIndex]
    self._safeTransfer(destination, rs.asset, total_deposited)

    # Update state
    ended: bool = rs.currentIndex + 1 >= len(rs.participants)
    self._rotating_savings[token_id] = RotatingSavings(
        participants=rs.participants,
        asset=rs.asset,
        amount=rs.amount,
        currentIndex=rs.currentIndex + 1,
        totalDeposited=0,
        tokenId=rs.tokenId,
        ended=ended,
        started=rs.started,
    )

    if ended:
        for participant: address in rs.participants:
            self._locked_collateral[participant][
                rs.tokenId
            ] -= amount_to_release
            self._free_collateral[participant][rs.asset] += amount_to_release
        log Ended(tokenId=rs.tokenId, lastUpdatedAt=block.timestamp)

    if is_claim:
        log Claimed(
            participant=destination,
            tokenId=rs.tokenId,
            index=rs.currentIndex,
            amount=rs.amount,
            totalDeposited=rs.totalDeposited,
        )
    else:
        log Skipped(
            destination=destination,
            tokenId=rs.tokenId,
            index=rs.currentIndex,
            amount=rs.amount,
        )


@internal
def _shuffleParticipants(token_id: uint256):
    word: bytes32 = keccak256(
        abi_encode(token_id, block.prevrandao, block.timestamp)
    )
    for i: uint256 in range(PARTICIPANTS_COUNT - 1):
        word = keccak256(concat(word, convert(i, bytes32)))
        span: uint256 = PARTICIPANTS_COUNT - i
        offset: uint256 = convert(word, uint256) % span
        j: uint256 = i + offset
        if j != i:
            tmp: address = self._rotating_savings[token_id].participants[i]
            self._rotating_savings[token_id].participants[i] = (
                self._rotating_savings[token_id].participants[j]
            )
            self._rotating_savings[token_id].participants[j] = tmp


@internal
def _safeTransferFrom(
    _from: address, _to: address, asset: address, amount: uint256
):
    initial: uint256 = staticcall IERC20(asset).balanceOf(_to)
    extcall IERC20(asset).transferFrom(_from, _to, amount)
    ending: uint256 = staticcall IERC20(asset).balanceOf(_to)
    assert initial + amount == ending, "pasanku: transferFrom failed"


@internal
def _safeTransfer(_to: address, asset: address, amount: uint256):
    initial: uint256 = staticcall IERC20(asset).balanceOf(_to)
    extcall IERC20(asset).transfer(_to, amount)
    ending: uint256 = staticcall IERC20(asset).balanceOf(_to)
    assert initial + amount == ending, "pasanku: transfer failed"


@internal
def _mint(owner: address, id: uint256):
    assert owner != empty(address), "ERC1155Mock: mint to the zero address"

    erc1155._before_token_transfer(
        empty(address),
        owner,
        erc1155._as_singleton_array(id),
        erc1155._as_singleton_array(MINT_TOKEN_AMOUNT),
        b"",
    )

    erc1155.balanceOf[owner][id] = unsafe_add(
        erc1155.balanceOf[owner][id], MINT_TOKEN_AMOUNT
    )
    log IERC1155.TransferSingle(
        _operator=msg.sender,
        _from=empty(address),
        _to=owner,
        _id=id,
        _value=MINT_TOKEN_AMOUNT,
    )

    erc1155._after_token_transfer(
        empty(address),
        owner,
        erc1155._as_singleton_array(id),
        erc1155._as_singleton_array(MINT_TOKEN_AMOUNT),
        b"",
    )
