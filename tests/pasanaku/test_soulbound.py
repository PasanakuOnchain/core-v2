import boa


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


def test_is_approved_for_all_always_false(pasanaku_contract, alice, bob):
    assert pasanaku_contract.isApprovedForAll(alice, bob) is False
