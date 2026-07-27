import boa

from tests.utils.constants import PARTICIPANT_COUNT, PASANAKU_AMOUNT_RAW, TOKEN_AMOUNT
from tests.utils.helpers import (
    create_and_join_all,
    create_pasanaku,
    fund_collateral_for_users,
)


def test_membership_not_minted_before_start(
    pasanaku_contract,
    owner,
    usdc_contract,
    users,
):
    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        [users[0]],
        PASANAKU_AMOUNT_RAW,
    )
    with boa.env.prank(users[0]):
        token_id = create_pasanaku(
            pasanaku_contract,
            PASANAKU_AMOUNT_RAW,
            PARTICIPANT_COUNT,
        )
    assert pasanaku_contract.total_supply(token_id) == 0
    assert pasanaku_contract.exists(token_id) is False


def test_membership_mints_to_every_participant_on_start(
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
    )
    assert pasanaku_contract.total_supply(token_id) == (
        PARTICIPANT_COUNT * TOKEN_AMOUNT
    )
    for user in users:
        assert pasanaku_contract.balanceOf(user, token_id) == TOKEN_AMOUNT
