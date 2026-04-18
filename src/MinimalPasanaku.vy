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


struct Pasanaku:
    token_id: uint256
    asset: address
    amount: uint256
    participants: DynArray[address, PARTICIPANT_COUNT]
    started: uint256
    updated: uint256
    ended: uint256


_counter: uint256
_pending_pasanakus: HashMap[uint256, Pasanaku]
_pasanakus: HashMap[uint256, Pasanaku]

# pasanaku_index -> tick_index
_active_participant: HashMap[uint256, uint256]

# participant -> asset -> amount deposited
_deposited: HashMap[address, HashMap[address, uint256]]

# participant -> asset -> amount in use
_in_use: HashMap[address, HashMap[address, uint256]]

# pasanaku_index -> tick_index -> participant -> deposited?
_deposited_for_token: HashMap[uint256, HashMap[uint256, HashMap[address, bool]]]

PARTICIPANT_COUNT: constant(uint256) = 12
TOKEN_MINT_AMOUNT: constant(uint256) = 1
DAYS_30: constant(uint256) = 30 * 24 * 60 * 60
SUPPORTED_ASSETS_COUNT: constant(uint256) = 3
SUPPORTED_ASSETS: immutable(address[SUPPORTED_ASSETS_COUNT])


@deploy
@payable
def __init__(
    base_uri_: String[80], supported_assets: address[SUPPORTED_ASSETS_COUNT]
):
    ow.__init__()
    erc1155.__init__(base_uri_)
    SUPPORTED_ASSETS = supported_assets


@external
@nonreentrant
def deposit(
    asset: address,
    amount: uint256,
    pasanaku_id: uint256,
    tick_index: uint256,
):
    assert amount > 0  # dev: invalid amount
    self._deposited[msg.sender][asset] += amount

    if pasanaku_id != empty(uint256) and tick_index != empty(uint256):
        self._deposit_for_token(msg.sender, amount, pasanaku_id, tick_index)

    extcall IERC20(asset).transferFrom(msg.sender, self, amount)

    log IPasanaku.CollateralDeposited(
        account=msg.sender,
        asset=asset,
        amount=amount,
        balance_after=self._deposited[msg.sender][asset],
    )


@external
def withdraw(asset: address, amount: uint256):
    assert amount > 0  # dev: invalid amount

    deposited: uint256 = self._deposited[msg.sender][asset]
    in_use: uint256 = self._in_use[msg.sender][asset]
    assert deposited > in_use  # dev: collateral in use
    assert deposited - in_use >= amount  # dev: collateral in use

    self._deposited[msg.sender][asset] -= amount
    extcall IERC20(asset).transfer(msg.sender, amount)

    log IPasanaku.CollateralWithdrawn(
        account=msg.sender,
        asset=asset,
        amount=amount,
        balance_after=self._deposited[msg.sender][asset],
    )


@external
def create_pasanaku(asset: address, amount: uint256) -> uint256:
    assert asset in SUPPORTED_ASSETS  # dev: unsupported asset

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
    self._pending_pasanakus[index] = pasanaku

    log IPasanaku.PasanakuCreated(
        pending_index=index,
        asset=asset,
        amount=amount,
    )
    return index


@external
def join_pasanaku(index: uint256):
    assert index < self._counter  # dev: invalid index

    pasanaku: Pasanaku = self._pending_pasanakus[index]
    assert msg.sender not in pasanaku.participants  # dev: participant already joined # nosplit

    pasanake_amount: uint256 = pasanaku.amount * PARTICIPANT_COUNT
    assert self._deposited[msg.sender][pasanaku.asset] >= pasanake_amount  # dev: insufficient collateral # nosplit

    pasanaku.participants.append(msg.sender)
    self._pending_pasanakus[index] = pasanaku
    self._in_use[msg.sender][pasanaku.asset] += pasanake_amount  # nosplit

    if len(pasanaku.participants) == PARTICIPANT_COUNT:
        self._start_pasanaku(index)

    log IPasanaku.PasanakuJoined(
        account=msg.sender,
        pending_index=index,
        participant_count=len(pasanaku.participants),
    )


@external
def tick(token_id: uint256):
    pasanaku: Pasanaku = self._pasanakus[token_id]
    assert pasanaku.started != empty(uint256)  # dev: pasanaku not started
    assert pasanaku.ended == empty(uint256)  # dev: pasanaku ended
    assert pasanaku.updated + DAYS_30 <= block.timestamp  # dev: not enough time passed # nosplit

    index: uint256 = self._active_participant[token_id]
    self._active_participant[token_id] += 1

    participant: address = pasanaku.participants[index]
    extcall IERC20(pasanaku.asset).transfer(participant, pasanaku.amount)

    if index == PARTICIPANT_COUNT - 1:
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
        ended=index == PARTICIPANT_COUNT - 1,
    )


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


@view
@external
def uri(id: uint256) -> String[512]:
    pasanaku: Pasanaku = self._pasanakus[id]
    if pasanaku.ended != empty(uint256):
        return "https://pasanaku.fun/pasanaku/ended"

    if pasanaku.started != empty(uint256):
        return "https://pasanaku.fun/pasanaku/started"
    
    return "https://pasanaku.fun/pasanaku/pending"


@view
@external
def isApprovedForAll(arg0: address, arg1: address) -> bool:
    return False


@external
@view
def pasanaku(pasanaku_id: uint256) -> Pasanaku:
    return self._pasanakus[pasanaku_id]


@external
@view
def pending_pasanaku(index: uint256) -> Pasanaku:
    return self._pending_pasanakus[index]


@external
@view
def deposited(participant: address, asset: address) -> uint256:
    return self._deposited[participant][asset]


@external
@view
def collateral_in_use(participant: address, asset: address) -> uint256:
    return self._in_use[participant][asset]


@external
@view
def deposited_for_token(
    pasanaku_id: uint256, tick_index: uint256, participant: address
) -> bool:
    return self._deposited_for_token[pasanaku_id][tick_index][participant]


@external
@view
def participant_count() -> uint256:
    return PARTICIPANT_COUNT


@view
@external
def supported_assets() -> address[SUPPORTED_ASSETS_COUNT]:
    return SUPPORTED_ASSETS


@internal
def _deposit_for_token(
    participant: address,
    amount: uint256,
    pasanaku_id: uint256,
    tick_index: uint256,
):
    pasanaku: Pasanaku = self._pasanakus[pasanaku_id]
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
    pasanaku: Pasanaku = self._pasanakus[index]
    pasanaku_id: uint256 = self._generate_pasanaku_id(
        pasanaku.asset, pasanaku.amount, pasanaku.participants
    )

    pasanaku.token_id = pasanaku_id
    pasanaku.started = block.timestamp
    self._pasanakus[pasanaku_id] = pasanaku
    self._pending_pasanakus[index] = empty(Pasanaku)

    for participant: address in pasanaku.participants:
        erc1155._safe_mint(participant, pasanaku_id, TOKEN_MINT_AMOUNT, b"")

    log IPasanaku.PasanakuStarted(
        token_id=pasanaku_id,
        pending_index=index,
        asset=pasanaku.asset,
        amount=pasanaku.amount,
        started_at=block.timestamp,
    )


@internal
@pure
def _generate_pasanaku_id(
    asset: address,
    amount: uint256,
    participants: DynArray[address, PARTICIPANT_COUNT],
) -> uint256:
    return convert(keccak256(abi_encode(asset, amount, participants)), uint256)
