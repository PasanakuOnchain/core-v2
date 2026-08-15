import pytest

from tests.fork.parity import ParityCase, run_parity_case
from tests.unitary.erc1155 import (
    test_membership_mint,
    test_soulbound,
    test_uri,
)

pytestmark = [pytest.mark.fork, pytest.mark.ignore_isolation]

CASES = [
    ParityCase(test_membership_mint.test_membership_not_minted_before_start),
    ParityCase(
        test_membership_mint.test_membership_mints_to_every_participant_on_start
    ),
    ParityCase(test_soulbound.test_safe_transfer_from_reverts),
    ParityCase(test_soulbound.test_safe_batch_transfer_from_reverts),
    ParityCase(test_soulbound.test_set_approval_for_all_reverts),
    ParityCase(test_soulbound.test_is_approved_for_all_always_false),
    ParityCase(test_soulbound.test_transfer_reverts_after_membership_mint),
    ParityCase(test_uri.test_uri_unknown_token_returns_invalid),
    ParityCase(test_uri.test_uri_created_token_returns_valid),
]


@pytest.mark.parametrize("case", CASES, ids=lambda case: case.id)
def test_fork_parity(request, case):
    run_parity_case(request, case)
