import boa

from tests.utils.constants import PARTICIPANT_COUNT, PASANAKU_AMOUNT_RAW
from tests.utils.helpers import (
    create_and_join_all,
    deposit_all_obligors,
    fund_collateral_for_users,
    generate_users,
    tick_and_claim,
    token_id_from_last_started,
)


def test_second_active_pasanaku_same_asset_starts(
    pasanaku_contract, owner, usdc_contract
):
    users = generate_users(PARTICIPANT_COUNT * 2)

    amount_raw = PASANAKU_AMOUNT_RAW
    create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users[:PARTICIPANT_COUNT],
        amount_raw,
    )
    assert pasanaku_contract.active_pasanaku_for_asset(usdc_contract.address) == 1

    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        users[PARTICIPANT_COUNT : PARTICIPANT_COUNT * 2 - 1],
        amount_raw,
    )
    with boa.env.prank(users[PARTICIPANT_COUNT]):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )
    for u in users[PARTICIPANT_COUNT + 1 : PARTICIPANT_COUNT * 2 - 1]:
        with boa.env.prank(u):
            pasanaku_contract.join_pasanaku(pending_idx)

    last_joiner = users[PARTICIPANT_COUNT * 2 - 1]
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [last_joiner], amount_raw
    )
    with boa.env.prank(last_joiner):
        pasanaku_contract.join_pasanaku(pending_idx)

    assert pasanaku_contract.active_pasanaku_for_asset(usdc_contract.address) == 2
    st = pasanaku_contract.pasanaku(pending_idx)
    assert st.started != 0


def test_pasanaku_starts_after_first_ends(
    pasanaku_contract, owner, usdc_contract, users, started_pasanaku
):
    tid0 = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    for round_idx in range(PARTICIPANT_COUNT):
        deposit_all_obligors(
            pasanaku_contract, tid0, users, round_idx, usdc_contract, owner, amount_raw
        )
        boa.env.time_travel(seconds=40 * 24 * 60 * 60)
        pasanaku_contract.tick(tid0)

    assert pasanaku_contract.active_pasanaku_for_asset(usdc_contract.address) == 0

    create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        amount_raw,
    )
    tid1 = token_id_from_last_started(pasanaku_contract)
    assert tid1 != tid0
    assert pasanaku_contract.active_pasanaku_for_asset(usdc_contract.address) == 1


def test_concurrent_pools_escrow_isolated(pasanaku_contract, owner, usdc_contract):
    users_a = generate_users(PARTICIPANT_COUNT)
    users_b = generate_users(PARTICIPANT_COUNT)

    amount_raw = PASANAKU_AMOUNT_RAW
    create_and_join_all(pasanaku_contract, usdc_contract, owner, users_a, amount_raw)
    tid_a = token_id_from_last_started(pasanaku_contract)

    create_and_join_all(pasanaku_contract, usdc_contract, owner, users_b, amount_raw)
    tid_b = token_id_from_last_started(pasanaku_contract)

    deposit_all_obligors(
        pasanaku_contract, tid_b, users_b, 0, usdc_contract, owner, amount_raw
    )

    escrow_b_before = pasanaku_contract.pool_escrow(tid_b)
    assert escrow_b_before == amount_raw * (PARTICIPANT_COUNT - 1)

    boa.env.time_travel(seconds=40 * 24 * 60 * 60)
    pasanaku_contract.tick(tid_a)

    assert pasanaku_contract.pool_escrow(tid_b) == escrow_b_before

    boa.env.time_travel(seconds=40 * 24 * 60 * 60)
    tick_and_claim(pasanaku_contract, tid_b, 0, users_b)

    recipient_b = users_b[0]
    expected = amount_raw * (PARTICIPANT_COUNT - 1)
    assert usdc_contract.balanceOf(recipient_b) == expected
    assert pasanaku_contract.pool_escrow(tid_b) == 0
