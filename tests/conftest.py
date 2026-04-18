import pytest
import boa
from src import Pasanaku as pasanaku
from tests.mocks import erc20_mock


BASE_URI = "https://pasanaku.fun/metadata/"
PASANAKU_AMOUNT_RAW = 100 * 10**6
DAYS_30 = 30 * 24 * 60 * 60


def token_id_from_last_started(pasanaku_contract):
    for log in reversed(pasanaku_contract.get_logs()):
        if type(log).__name__ == "PasanakuStarted":
            return log.token_id
    raise RuntimeError("PasanakuStarted log not found")


def fund_and_join_all(pasanaku_contract, asset, owner, users, amount_raw, pending_idx):
    need = amount_raw * 12
    for u in users:
        with boa.env.prank(owner):
            asset.mint(u, need)
        with boa.env.prank(u):
            asset.approve(pasanaku_contract.address, need)
            pasanaku_contract.deposit(asset.address, need, 0, 0)
    for u in users:
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
def twelve_users():
    addrs = []
    for _ in range(12):
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
def pasanaku_contract(owner, usdc_contract, usdt_contract, weth_contract):
    assets = [usdc_contract.address, usdt_contract.address, weth_contract.address]
    with boa.env.prank(owner):
        return pasanaku.deploy(BASE_URI, assets)


@pytest.fixture
def started_pasanaku(pasanaku_contract, owner, usdc_contract, twelve_users):
    amount_raw = PASANAKU_AMOUNT_RAW
    with boa.env.prank(owner):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )
    fund_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        twelve_users,
        amount_raw,
        pending_idx,
    )
    token_id = token_id_from_last_started(pasanaku_contract)
    return {
        "token_id": token_id,
        "pending_idx": pending_idx,
        "asset": usdc_contract,
        "amount_raw": amount_raw,
        "users": twelve_users,
    }
