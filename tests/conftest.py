import pytest
import boa
from src import pasanaku
from src._mocks import erc20_mock


LOBBY_AMOUNT = 100 * 10**6


@pytest.fixture
def owner():
    initial_balance = int(10**18)
    addr = boa.env.generate_address()
    boa.env.set_balance(addr, initial_balance)
    return addr


@pytest.fixture
def bob():
    initial_balance = int(10**18)
    addr = boa.env.generate_address()
    boa.env.set_balance(addr, initial_balance)
    return addr


@pytest.fixture
def alice():
    initial_balance = int(10**18)
    addr = boa.env.generate_address()
    boa.env.set_balance(addr, initial_balance)
    return addr


@pytest.fixture
def users():
    addrs = []
    for _ in range(12):
        initial_balance = int(10**18)
        addr = boa.env.generate_address()
        boa.env.set_balance(addr, initial_balance)
        addrs.append(addr)
    return addrs


@pytest.fixture
def usdc_contract(owner):
    with boa.env.prank(owner):
        return erc20_mock.deploy(
            "USD Coin",
            "USDC",
            6,
            int(10_000 * 10**6),
            "fake-usdc",
            "1",
        )


@pytest.fixture
def usdt_contract(owner):
    with boa.env.prank(owner):
        return erc20_mock.deploy(
            "Tether",
            "USDT",
            6,
            int(10_000 * 10**6),
            "fake-usdt",
            "1",
        )


@pytest.fixture
def weth_contract(owner):
    with boa.env.prank(owner):
        return erc20_mock.deploy(
            "Wrapped Ether",
            "WETH",
            18,
            int(10_000 * 10**18),
            "fake-weth",
            "1",
        )


@pytest.fixture
def tokens(usdc_contract, usdt_contract, weth_contract):
    return [usdc_contract, usdt_contract, weth_contract]


@pytest.fixture
def pasanaku_contract(owner, usdc_contract, usdt_contract, weth_contract):
    with boa.env.prank(owner):
        return pasanaku.deploy([usdc_contract, usdt_contract, weth_contract])


@pytest.fixture
def protocol_fee():
    return int(0.000075 * 10**18)


@pytest.fixture
def lobby_amount():
    return LOBBY_AMOUNT


@pytest.fixture
def funded_users(users, owner, usdc_contract, pasanaku_contract):
    collateral_per_user = LOBBY_AMOUNT * 11
    for user in users:
        with boa.env.prank(owner):
            usdc_contract.mint(user, collateral_per_user)
        with boa.env.prank(user):
            usdc_contract.approve(pasanaku_contract.address, collateral_per_user)
            pasanaku_contract.addCollateral(usdc_contract.address, collateral_per_user)
    return users


@pytest.fixture
def lobby_id(pasanaku_contract, owner, usdc_contract, protocol_fee):
    with boa.env.prank(owner):
        return pasanaku_contract.create(
            usdc_contract.address, LOBBY_AMOUNT, value=protocol_fee
        )


@pytest.fixture
def full_lobby(pasanaku_contract, funded_users, lobby_id, protocol_fee):
    for user in funded_users:
        with boa.env.prank(user):
            pasanaku_contract.join(lobby_id, value=protocol_fee)
    return lobby_id


@pytest.fixture
def started_lobby(pasanaku_contract, full_lobby, funded_users):
    with boa.env.prank(funded_users[0]):
        pasanaku_contract.finalizeLobby(full_lobby)
    return full_lobby
