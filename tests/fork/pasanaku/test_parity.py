import pytest

from tests.fork.parity import ParityCase, run_parity_case
from tests.unitary.pasanaku import (
    test_admin,
    test_collateral,
    test_concurrency,
    test_deposit,
    test_fees,
    test_lifecycle,
    test_tick_claim,
)

pytestmark = [pytest.mark.fork, pytest.mark.ignore_isolation]

CASES = [
    ParityCase(test_admin.test_accept_ownership),
    ParityCase(test_admin.test_set_stale_time_owner_updates),
    ParityCase(test_admin.test_set_stale_time_non_owner_reverts),
    ParityCase(test_admin.test_set_stale_time_outside_bounds_reverts),
    ParityCase(test_collateral.test_deposit_credits_vault_shares),
    ParityCase(test_collateral.test_withdraw_burns_only_free_shares),
    ParityCase(test_collateral.test_redeem_returns_assets),
    ParityCase(test_collateral.test_locked_shares_cannot_be_withdrawn),
    ParityCase(test_collateral.test_pledge_uses_configured_participant_count),
    ParityCase(test_concurrency.test_two_pools_can_run_on_same_vault),
    ParityCase(test_concurrency.test_concurrent_pool_escrow_is_isolated),
    ParityCase(test_deposit.test_obligor_deposit_is_recorded),
    ParityCase(test_deposit.test_round_recipient_cannot_deposit),
    ParityCase(test_deposit.test_duplicate_round_deposit_reverts),
    ParityCase(test_deposit.test_wrong_round_amount_reverts),
    ParityCase(test_fees.test_fee_defaults_to_constructor_value),
    ParityCase(test_fees.test_yield_fee_defaults_to_constructor_value),
    ParityCase(test_fees.test_owner_can_update_fee),
    ParityCase(test_fees.test_owner_can_update_yield_fee),
    ParityCase(test_fees.test_non_owner_cannot_update_fee),
    ParityCase(test_fees.test_non_owner_cannot_update_yield_fee),
    ParityCase(test_fees.test_fee_above_max_reverts),
    ParityCase(test_fees.test_yield_fee_above_max_reverts),
    ParityCase(test_fees.test_create_requires_configured_fee),
    ParityCase(test_fees.test_collect_fees_sends_native_balance_to_owner),
    ParityCase(test_lifecycle.test_deploy_uses_one_asset_and_vault),
    *[
        ParityCase(
            test_lifecycle.test_create_rejects_unsupported_participant_count,
            {"participant_count": participant_count},
        )
        for participant_count in (5, 7, 11, 13)
    ],
    *[
        ParityCase(
            test_lifecycle.test_pasanaku_starts_at_configured_size,
            {"participant_count": participant_count},
        )
        for participant_count in (6, 12)
    ],
    ParityCase(test_lifecycle.test_create_and_join_lock_shares),
    ParityCase(test_lifecycle.test_pre_start_yield_remains_with_depositor),
    ParityCase(test_lifecycle.test_leave_stale_pool_returns_locked_shares),
    ParityCase(test_lifecycle.test_join_stale_pool_reverts_and_leave_still_works),
    ParityCase(test_lifecycle.test_stale_time_is_snapshotted_per_pool),
    ParityCase(test_tick_claim.test_tick_accrues_and_claims_full_round_payout),
    ParityCase(test_tick_claim.test_miss_funds_recipient_and_moves_penalty_to_reserve),
    ParityCase(test_tick_claim.test_last_tick_returns_principal_and_clears_locks),
    ParityCase(
        test_tick_claim.test_end_distributes_vault_yield_by_participant_position
    ),
    ParityCase(test_tick_claim.test_end_accrues_yield_fee_shares_until_owner_collects),
    ParityCase(
        test_tick_claim.test_renouncing_ownership_does_not_block_final_settlement
    ),
    ParityCase(
        test_tick_claim.test_reserve_covers_vault_loss_before_surplus_distribution
    ),
    ParityCase(
        test_tick_claim.test_end_allocates_small_reserve_cumulatively_across_shortfalls
    ),
    ParityCase(test_tick_claim.test_miss_uses_combined_withdraw_preview),
    ParityCase(
        test_tick_claim.test_miss_reserves_penalty_when_combined_preview_gap_is_zero
    ),
    ParityCase(
        test_tick_claim.test_miss_reserves_remaining_tip_when_principal_is_still_covered
    ),
    ParityCase(
        test_tick_claim.test_underwater_miss_settles_partial_payout_and_pool_can_finish
    ),
    ParityCase(test_tick_claim.test_empty_vault_miss_does_not_block_pool_completion),
    ParityCase(test_tick_claim.test_tick_too_early_reverts),
]


@pytest.mark.parametrize("case", CASES, ids=lambda case: case.id)
def test_fork_parity(request, case):
    run_parity_case(request, case)
