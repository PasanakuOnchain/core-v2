import boa

from tests.utils.constants import DAYS_3, DAYS_7


def test_accept_ownership(pasanaku_contract, owner, alice):
    assert pasanaku_contract.owner() == owner
    with boa.env.prank(owner):
        pasanaku_contract.transfer_ownership(alice)
    assert pasanaku_contract.pending_owner() == alice
    with boa.env.prank(alice):
        pasanaku_contract.accept_ownership()
    assert pasanaku_contract.owner() == alice


def test_set_stale_time_owner_updates(pasanaku_contract, owner):
    with boa.env.prank(owner):
        pasanaku_contract.set_stale_time(DAYS_3)

    stale_logs = [
        log for log in pasanaku_contract.get_logs() if type(log).__name__ == "StaleTimeSet"
    ]
    assert len(stale_logs) == 1
    assert stale_logs[0].days == DAYS_3


def test_set_stale_time_non_owner_reverts(pasanaku_contract, alice):
    with boa.reverts():
        with boa.env.prank(alice):
            pasanaku_contract.set_stale_time(DAYS_3)


def test_set_stale_time_below_min_reverts(pasanaku_contract, owner):
    too_short = DAYS_3 - 1
    with boa.reverts(dev="pasanaku stale time out of range"):
        with boa.env.prank(owner):
            pasanaku_contract.set_stale_time(too_short)


def test_set_stale_time_above_max_reverts(pasanaku_contract, owner):
    too_long = DAYS_7 + 1
    with boa.reverts(dev="pasanaku stale time out of range"):
        with boa.env.prank(owner):
            pasanaku_contract.set_stale_time(too_long)


def test_set_stale_time_at_bounds(pasanaku_contract, owner):
    with boa.env.prank(owner):
        pasanaku_contract.set_stale_time(DAYS_3)
    with boa.env.prank(owner):
        pasanaku_contract.set_stale_time(DAYS_7)
