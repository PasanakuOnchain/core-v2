import boa
import pytest

from tests.utils.constants import PARTICIPANT_COUNT


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
