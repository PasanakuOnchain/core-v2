# pragma version ==0.4.3
# pragma nonreentrancy off

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


# @dev We import and initialise the `erc1155` module.
from snekmate.tokens import erc1155
initializes: erc1155[ownable := ow]
exports: erc1155.__interface__


struct Pasanaku:
    token_id: uint256
    asset: address
    amount: uint256
    participants: DynArray[address, PARTICIPANT_COUNT]
    started: uint256
    updated: uint256
    ended: uint256


_counter: uint256
_pasanakus: HashMap[uint256, Pasanaku]
_active_participant: HashMap[uint256, uint256]
_deposited: HashMap[address, HashMap[address, uint256]]
_deposited_in_use: HashMap[address, HashMap[address, uint256]]

PARTICIPANT_COUNT: constant(uint256) = 12
TOKEN_AMOUNT: constant(uint256) = 1
ONE_DAY: constant(uint256) = 1 * 24 * 60 * 60
THIRTY_DAYS: constant(uint256) = 30 * ONE_DAY


@deploy
@payable
def __init__(base_uri_: String[80]):
    ow.__init__()
    erc1155.__init__(base_uri_)


@external
@nonreentrant
def deposit(asset: address, amount: uint256):
    assert amount > 0 # dev: invalid amount
    self._deposited[msg.sender][asset] += amount
    extcall IERC20(asset).transferFrom(msg.sender, self, amount)


@external
def withdraw(asset: address, amount: uint256):
    assert amount > 0 # dev: invalid amount

    deposited: uint256 = self._deposited[msg.sender][asset]
    deposited_in_use: uint256 = self._deposited_in_use[msg.sender][asset]
    assert deposited > deposited_in_use # dev: insufficient balance
    assert deposited - deposited_in_use >= amount # dev: insufficient balance

    self._deposited[msg.sender][asset] -= amount
    extcall IERC20(asset).transfer(msg.sender, amount)


@external
def create_pasanaku(asset: address, amount: uint256) -> uint256:
    index: uint256 = self._counter
    self._counter += 1

    pasanaku: Pasanaku = Pasanaku(
        token_id=empty(uint256),
        asset=asset,
        amount=amount,
        participants=empty(DynArray[address, PARTICIPANT_COUNT]),
        started=empty(uint256),
        updated=empty(uint256),
        ended=empty(uint256),
    )
    self._pasanakus[index] = pasanaku
    return index


@external
def join_pasanaku(index: uint256):
    assert index < self._counter # dev: invalid index

    pasanaku: Pasanaku = self._pasanakus[index]
    assert msg.sender not in pasanaku.participants # dev: participant already joined # nosplit

    pasanaku.participants.append(msg.sender)
    self._pasanakus[index] = pasanaku
    self._deposited_in_use[msg.sender][pasanaku.asset] += pasanaku.amount * PARTICIPANT_COUNT # nosplit

    if len(pasanaku.participants) == PARTICIPANT_COUNT:
        self._start_pasanaku(index)



@external
def tick(token_id: uint256):
    pasanaku: Pasanaku = self._pasanakus[token_id]
    assert pasanaku.started != 0 # dev: pasanaku not started
    assert pasanaku.ended == 0 # dev: pasanaku ended
    assert block.timestamp >= pasanaku.updated + THIRTY_DAYS # dev: not enough time passed

    index: uint256 = self._active_participant[token_id]
    self._active_participant[token_id] += 1
    pasanaku.updated = block.timestamp

    participant: address = pasanaku.participants[index]
    extcall IERC20(pasanaku.asset).transfer(participant, pasanaku.amount)

    if index + 1 == PARTICIPANT_COUNT:
        pasanaku.ended = block.timestamp
    self._pasanakus[token_id] = pasanaku


@external
@view
def participant_count() -> uint256:
    return PARTICIPANT_COUNT


@internal
def _start_pasanaku(index: uint256):
    pasanaku: Pasanaku = self._pasanakus[index]
    token_id: uint256 = self._generate_token_id(
        pasanaku.asset, pasanaku.amount, pasanaku.participants
    )

    pasanaku.token_id = token_id
    pasanaku.started = block.timestamp
    self._pasanakus[index] = pasanaku

    for participant: address in pasanaku.participants:
        erc1155._safe_mint(participant, token_id, TOKEN_AMOUNT, b"")


@internal
@pure
def _generate_token_id(
    asset: address,
    amount: uint256,
    participants: DynArray[address, PARTICIPANT_COUNT],
) -> uint256:
    return convert(keccak256(abi_encode(asset, amount, participants)), uint256)
