import boa

from tests.conftest import DAYS_30


def test_safe_transfer_from_reverts(pasanaku_contract, alice, bob):
    with boa.reverts("pasanaku: pasanakus are soul-bounded tokens"):
        with boa.env.prank(alice):
            pasanaku_contract.safeTransferFrom(alice, bob, 0, 1, b"")


def test_safe_batch_transfer_from_reverts(pasanaku_contract, alice, bob):
    with boa.reverts("pasanaku: pasanakus are soul-bounded tokens"):
        with boa.env.prank(alice):
            pasanaku_contract.safeBatchTransferFrom(alice, bob, [0], [1], b"")


def test_set_approval_for_all_reverts(pasanaku_contract, alice, bob):
    with boa.reverts("pasanaku: pasanakus are soul-bounded tokens"):
        with boa.env.prank(alice):
            pasanaku_contract.setApprovalForAll(bob, True)


def test_is_approved_for_all_always_false(pasanaku_contract, twelve_users):
    for userA in twelve_users:
        for userB in twelve_users:
            if userA != userB:
                assert pasanaku_contract.isApprovedForAll(userA, userB) is False


def test_uri_unknown_token_pending(pasanaku_contract):
    assert pasanaku_contract.uri(2**256 - 1) == "https://pasanaku.fun/pasanaku/pending"


def test_uri_started_game(pasanaku_contract, started_pasanaku):
    tid = started_pasanaku["token_id"]
    assert pasanaku_contract.uri(tid) == "https://pasanaku.fun/pasanaku/started"


def test_uri_ended_game(pasanaku_contract, started_pasanaku):
    tid = started_pasanaku["token_id"]
    for _ in range(12):
        boa.env.time_travel(seconds=DAYS_30)
        pasanaku_contract.tick(tid)
    assert pasanaku_contract.uri(tid) == "https://pasanaku.fun/pasanaku/ended"
