import boa

from tests.utils.constants import DAYS_3, DAYS_7


def test_accept_ownership(pasanaku_contract, owner, alice):
    with boa.env.prank(owner):
        pasanaku_contract.transfer_ownership(alice)
    with boa.env.prank(alice):
        pasanaku_contract.accept_ownership()
    assert pasanaku_contract.owner() == alice


def test_set_stale_time_owner_updates(pasanaku_contract, owner):
    with boa.env.prank(owner):
        pasanaku_contract.set_stale_time(DAYS_3)
    assert pasanaku_contract.stale_time() == DAYS_3


def test_set_stale_time_non_owner_reverts(pasanaku_contract, alice):
    with boa.reverts():
        with boa.env.prank(alice):
            pasanaku_contract.set_stale_time(DAYS_3)


def test_set_stale_time_outside_bounds_reverts(pasanaku_contract, owner):
    with boa.env.prank(owner):
        with boa.reverts(dev="stale time out of range"):
            pasanaku_contract.set_stale_time(DAYS_3 - 1)
        with boa.reverts(dev="stale time out of range"):
            pasanaku_contract.set_stale_time(DAYS_7 + 1)
