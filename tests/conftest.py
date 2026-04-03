import pytest
import boa
from src import pasanaku
from src._mocks import erc20_mock


@pytest.fixture
def owner():
    initial_balance = int(10**18)
    addr = boa.env.generate_address()
    boa.env.set_balance(addr, initial_balance)
    return addr


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
def pasanaku_contract(owner, usdc_contract, usdt_contract, weth_contract):
    with boa.env.prank(owner):
        return pasanaku.deploy(
        [usdc_contract, usdt_contract, weth_contract]
    )
