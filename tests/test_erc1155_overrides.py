import boa

from tests.conftest import (
    DAYS_3,
    DAYS_40,
    PARTICIPANT_COUNT,
    PASANAKU_AMOUNT_RAW,
    URI_ENDED,
    URI_NOT_CREATED,
    URI_ONGOING,
    URI_PENDING,
    URI_STALE,
    fund_collateral_for_users,
)


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


def test_uri_unknown_token_not_created(pasanaku_contract):
    assert pasanaku_contract.uri(2**256 - 1) == URI_NOT_CREATED


def test_uri_pending_token(pasanaku_contract, owner, users, usdc_contract):
    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        [users[0]],
        PASANAKU_AMOUNT_RAW,
    )
    with boa.env.prank(users[0]):
        pasanaku_contract.create_pasanaku(usdc_contract.address, PASANAKU_AMOUNT_RAW)
    assert pasanaku_contract.uri(0) == URI_PENDING


def test_uri_stale_pending_pasanaku(pasanaku_contract, owner, users, usdc_contract):
    with boa.env.prank(owner):
        pasanaku_contract.set_stale_time(DAYS_3)
    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        [users[0]],
        PASANAKU_AMOUNT_RAW,
    )
    with boa.env.prank(users[0]):
        token_id = pasanaku_contract.create_pasanaku(
            usdc_contract.address, PASANAKU_AMOUNT_RAW
        )
    assert pasanaku_contract.uri(token_id) == URI_PENDING

    boa.env.time_travel(seconds=DAYS_3)
    assert pasanaku_contract.uri(token_id) == URI_STALE


def test_uri_started_game(pasanaku_contract, started_pasanaku):
    tid = started_pasanaku["token_id"]
    assert pasanaku_contract.uri(tid) == URI_ONGOING


def test_uri_ended_game(pasanaku_contract, owner, usdc_contract, started_pasanaku):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    for round_idx in range(PARTICIPANT_COUNT):
        recipient = users[round_idx]
        for u in users:
            if u == recipient:
                continue
            with boa.env.prank(owner):
                usdc_contract.mint(u, amount_raw)
            with boa.env.prank(u):
                usdc_contract.approve(pasanaku_contract.address, amount_raw)
                pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(tid)

    assert pasanaku_contract.uri(tid) == URI_ENDED
