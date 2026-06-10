import boa
import pytest

boa.env.enable_fast_mode()

from src import Pasanaku as pasanaku
from tests.mocks import erc20_mock
from tests.utils.constants import PASANAKU_AMOUNT_RAW, PARTICIPANT_COUNT
from tests.utils.helpers import create_and_join_all, token_id_from_last_started


@pytest.fixture(scope="module")
def owner():
    addr = boa.env.generate_address()
    boa.env.set_balance(addr, 10**18)
    return addr


@pytest.fixture
def alice():
    addr = boa.env.generate_address()
    boa.env.set_balance(addr, 10**18)
    return addr


@pytest.fixture
def bob():
    addr = boa.env.generate_address()
    boa.env.set_balance(addr, 10**18)
    return addr


@pytest.fixture
def users():
    addrs = []
    for _ in range(PARTICIPANT_COUNT):
        addr = boa.env.generate_address()
        boa.env.set_balance(addr, 10**18)
        addrs.append(addr)
    return addrs


@pytest.fixture(scope="module")
def usdc_contract(owner):
    with boa.env.prank(owner):
        return erc20_mock.deploy(
            "USD Coin",
            "USDC",
            6,
            10_000,
            "fake-usdc",
            "1",
        )


@pytest.fixture(scope="module")
def usdt_contract(owner):
    with boa.env.prank(owner):
        return erc20_mock.deploy(
            "Tether",
            "USDT",
            6,
            10_000,
            "fake-usdt",
            "1",
        )


@pytest.fixture(scope="module")
def weth_contract(owner):
    with boa.env.prank(owner):
        return erc20_mock.deploy(
            "Wrapped Ether",
            "WETH",
            18,
            10_000,
            "fake-weth",
            "1",
        )


@pytest.fixture(scope="module")
def dai_contract(owner):
    with boa.env.prank(owner):
        return erc20_mock.deploy(
            "Dai Stablecoin",
            "DAI",
            18,
            10_000,
            "fake-dai",
            "1",
        )


@pytest.fixture(scope="module")
def pasanaku_contract(
    owner,
    usdc_contract,
    usdt_contract,
    weth_contract,
    dai_contract,
):
    assets = [
        usdc_contract.address,
        usdt_contract.address,
        weth_contract.address,
        dai_contract.address,
    ]
    with boa.env.prank(owner):
        return pasanaku.deploy(assets)


@pytest.fixture
def started_pasanaku(pasanaku_contract, owner, usdc_contract, users):
    amount_raw = PASANAKU_AMOUNT_RAW
    create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        amount_raw,
    )
    token_id = token_id_from_last_started(pasanaku_contract)
    return {
        "token_id": token_id,
        "amount_raw": amount_raw,
        "users": users,
    }
