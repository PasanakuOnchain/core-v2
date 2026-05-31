import boa
import pytest

from src import pasanaku
from tests.mocks import erc20_mock

PASANAKU_AMOUNT_RAW = 100 * 10**6
DAYS_40 = 40 * 24 * 60 * 60
PARTICIPANT_COUNT = 9
_MISS_PENALTY_BPS = 5
_BPS_PRECISION = 10000


def pledge(amount_raw: int) -> int:
    return (
        amount_raw * PARTICIPANT_COUNT
        + amount_raw * PARTICIPANT_COUNT * _MISS_PENALTY_BPS // _BPS_PRECISION
    )


def penalty_per_amount(amount_raw: int) -> int:
    return amount_raw * _MISS_PENALTY_BPS // 10_000


def token_id_from_last_started(pasanaku_contract):
    for log in reversed(pasanaku_contract.get_logs()):
        if type(log).__name__ == "PasanakuStarted":
            return log.token_id
    raise RuntimeError("PasanakuStarted log not found")


def fund_collateral_for_users(
    pasanaku_contract, asset, owner, users, amount_raw, raw=False
):
    need = amount_raw if raw else pledge(amount_raw)
    for u in users:
        with boa.env.prank(owner):
            asset.mint(u, need)
        with boa.env.prank(u):
            asset.approve(pasanaku_contract.address, need)
            pasanaku_contract.add_collateral(asset.address, need)


def create_and_join_all(pasanaku_contract, asset, owner, users, amount_raw):
    fund_collateral_for_users(pasanaku_contract, asset, owner, users, amount_raw)
    with boa.env.prank(users[0]):
        pending_idx = pasanaku_contract.create_pasanaku(asset.address, amount_raw)
    for u in users[1:]:
        with boa.env.prank(u):
            pasanaku_contract.join_pasanaku(pending_idx)


@pytest.fixture
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
def nine_users():
    addrs = []
    for _ in range(PARTICIPANT_COUNT):
        addr = boa.env.generate_address()
        boa.env.set_balance(addr, 10**18)
        addrs.append(addr)
    return addrs


@pytest.fixture
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


@pytest.fixture
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


@pytest.fixture
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


@pytest.fixture
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


@pytest.fixture
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
def started_pasanaku(pasanaku_contract, owner, usdc_contract, nine_users):
    amount_raw = PASANAKU_AMOUNT_RAW
    create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        nine_users,
        amount_raw,
    )
    token_id = token_id_from_last_started(pasanaku_contract)
    return {
        "token_id": token_id,
        "amount_raw": amount_raw,
        "users": nine_users,
    }
