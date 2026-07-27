import boa

from tests.utils.constants import DAYS_40, PARTICIPANT_COUNT, PASANAKU_AMOUNT_RAW
from tests.utils.helpers import (
    create_and_join_all,
    deposit_all_obligors,
    generate_users,
)


def test_two_pools_can_run_on_same_vault(
    pasanaku_contract,
    usdc_contract,
    owner,
):
    users_a = generate_users(PARTICIPANT_COUNT)
    users_b = generate_users(PARTICIPANT_COUNT)
    create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users_a,
        PASANAKU_AMOUNT_RAW,
    )
    create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users_b,
        PASANAKU_AMOUNT_RAW,
    )
    assert pasanaku_contract.active_pasanaku_count() == 2


def test_concurrent_pool_escrow_is_isolated(
    pasanaku_contract,
    usdc_contract,
    owner,
):
    users_a = generate_users(PARTICIPANT_COUNT)
    users_b = generate_users(PARTICIPANT_COUNT)
    token_a = create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users_a,
        PASANAKU_AMOUNT_RAW,
    )
    token_b = create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users_b,
        PASANAKU_AMOUNT_RAW,
    )
    deposit_all_obligors(
        pasanaku_contract,
        token_b,
        users_b,
        0,
        usdc_contract,
        owner,
        PASANAKU_AMOUNT_RAW,
    )
    escrow_b = pasanaku_contract.pool_escrow(token_b)
    boa.env.time_travel(seconds=DAYS_40)
    pasanaku_contract.tick(token_a)
    assert pasanaku_contract.pool_escrow(token_b) == escrow_b
