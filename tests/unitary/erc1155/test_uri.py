import boa

from tests.utils.constants import (
    DAYS_3,
    DAYS_40,
    PARTICIPANT_COUNT,
    PASANAKU_AMOUNT_RAW,
    URI_ENDED,
    URI_NOT_CREATED,
    URI_ONGOING,
    URI_PENDING,
    URI_STALE,
)
from tests.utils.helpers import (
    create_pasanaku,
    deposit_all_obligors,
    fund_collateral_for_users,
)


def test_uri_unknown_token_not_created(pasanaku_contract):
    assert pasanaku_contract.uri(2**256 - 1) == URI_NOT_CREATED


def test_uri_token_id_equals_counter_not_created(pasanaku_contract):
    """token_id == counter means not yet created."""
    assert pasanaku_contract.uri(0) == URI_NOT_CREATED


def test_uri_pending_token(pasanaku_contract, owner, users, usdc_contract):
    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        [users[0]],
        PASANAKU_AMOUNT_RAW,
    )
    with boa.env.prank(users[0]):
        create_pasanaku(pasanaku_contract, usdc_contract.address, PASANAKU_AMOUNT_RAW)
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
        token_id = create_pasanaku(
            pasanaku_contract, usdc_contract.address, PASANAKU_AMOUNT_RAW
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
        deposit_all_obligors(
            pasanaku_contract, tid, users, round_idx, usdc_contract, owner, amount_raw
        )
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(tid)

    assert pasanaku_contract.uri(tid) == URI_ENDED
