import boa
import pytest

from src import Pasanaku as pasanaku
from tests.mocks import erc20_mock, erc4626_mock
from tests.utils.constants import PASANAKU_AMOUNT_RAW, PARTICIPANT_COUNT
from tests.utils.helpers import create_and_join_all

boa.env.enable_fast_mode()


@pytest.fixture(scope="module")
def owner():
    addr = boa.env.generate_address(alias="owner")
    boa.env.set_balance(addr, 10**18)
    return addr


@pytest.fixture
def alice():
    addr = boa.env.generate_address(alias="alice")
    boa.env.set_balance(addr, 10**18)
    return addr


@pytest.fixture
def bob():
    addr = boa.env.generate_address(alias="bob")
    boa.env.set_balance(addr, 10**18)
    return addr


@pytest.fixture
def users():
    addrs = []
    for index in range(PARTICIPANT_COUNT):
        addr = boa.env.generate_address(alias=f"participant-{index}")
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
def vault_contract(owner, usdc_contract):
    with boa.env.prank(owner):
        return erc4626_mock.deploy(usdc_contract.address)


@pytest.fixture(scope="module")
def pasanaku_contract(owner, usdc_contract, vault_contract):
    with boa.env.prank(owner):
        return pasanaku.deploy(
            usdc_contract.address,
            vault_contract.address,
            0,
            505,
        )


@pytest.fixture
def started_pasanaku(
    pasanaku_contract,
    owner,
    usdc_contract,
    users,
):
    token_id = create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        PASANAKU_AMOUNT_RAW,
        PARTICIPANT_COUNT,
    )
    return {
        "token_id": token_id,
        "amount_raw": PASANAKU_AMOUNT_RAW,
        "participant_count": PARTICIPANT_COUNT,
        "users": users,
    }
