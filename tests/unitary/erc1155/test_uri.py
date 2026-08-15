import boa

from tests.utils.constants import (
    PASANAKU_AMOUNT_RAW,
    URI_INVALID,
    URI_VALID,
)
from tests.utils.helpers import (
    create_pasanaku,
    fund_collateral_for_users,
)


def test_uri_unknown_token_returns_invalid(pasanaku_contract):
    assert pasanaku_contract.uri(0) == URI_INVALID


def test_uri_created_token_returns_valid(
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
            6,
        )
    assert pasanaku_contract.uri(token_id) == URI_VALID
    assert pasanaku_contract.uri(token_id + 1) == URI_INVALID
