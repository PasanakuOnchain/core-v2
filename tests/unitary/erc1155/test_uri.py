import boa

from tests.utils.constants import (
    DAYS_3,
    PASANAKU_AMOUNT_RAW,
    URI_ENDED,
    URI_NOT_CREATED,
    URI_ONGOING,
    URI_PENDING,
    URI_STALE,
)
from tests.utils.helpers import (
    create_pasanaku,
    fund_collateral_for_users,
    run_all_rounds,
)


def test_uri_unknown_token(pasanaku_contract):
    assert pasanaku_contract.uri(0) == URI_NOT_CREATED


def test_uri_pending_and_stale(
    pasanaku_contract,
    owner,
    usdc_contract,
    users,
):
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
        token_id = create_pasanaku(
            pasanaku_contract,
            PASANAKU_AMOUNT_RAW,
            6,
        )
    assert pasanaku_contract.uri(token_id) == URI_PENDING
    boa.env.time_travel(seconds=DAYS_3)
    assert pasanaku_contract.uri(token_id) == URI_STALE


def test_uri_started_and_ended(
    pasanaku_contract,
    owner,
    usdc_contract,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    assert pasanaku_contract.uri(token_id) == URI_ONGOING
    run_all_rounds(
        pasanaku_contract,
        token_id,
        started_pasanaku["users"],
        usdc_contract,
        owner,
        started_pasanaku["amount_raw"],
    )
    assert pasanaku_contract.uri(token_id) == URI_ENDED
