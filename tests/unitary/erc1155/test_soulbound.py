import boa

from tests.utils.constants import TOKEN_AMOUNT


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


def test_is_approved_for_all_always_false(pasanaku_contract, users):
    for user_a in users:
        for user_b in users:
            if user_a != user_b:
                assert pasanaku_contract.isApprovedForAll(user_a, user_b) is False


def test_transfer_reverts_after_membership_mint(
    pasanaku_contract, started_pasanaku, bob
):
    """Soul-bound: transfer reverts even when holder owns a membership receipt."""
    tid = started_pasanaku["token_id"]
    holder = started_pasanaku["users"][0]
    assert pasanaku_contract.balanceOf(holder, tid) == TOKEN_AMOUNT

    with boa.reverts("pasanaku: pasanakus are soul-bounded tokens"):
        with boa.env.prank(holder):
            pasanaku_contract.safeTransferFrom(holder, bob, tid, TOKEN_AMOUNT, b"")
