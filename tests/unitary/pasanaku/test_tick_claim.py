import boa

from tests.utils.constants import (
    _MIN_TIME_INTERVAL,
    MAX_YIELD_FEE,
    PARTICIPANT_COUNT,
)
from tests.utils.helpers import (
    create_and_join_all,
    deposit_all_obligors,
    donate_yield,
    penalty_per_amount,
    pledge,
    run_all_rounds,
)


def _deposit_except(
    pasanaku,
    asset,
    owner,
    users,
    recipient,
    excluded,
    amount,
    token_id,
):
    for user in users:
        if user == recipient or user == excluded:
            continue
        with boa.env.prank(owner):
            asset.mint(user, amount)
        with boa.env.prank(user):
            asset.approve(pasanaku.address, amount)
            pasanaku.deposit_to_pasanaku(amount, token_id, user)


def _weighted_distributions(yield_shares, participant_count):
    total_weight = participant_count * (participant_count + 1) // 2
    distributions = []
    distributed = 0
    for index in range(participant_count):
        if index == participant_count - 1:
            amount = yield_shares - distributed
        else:
            amount = yield_shares * (index + 1) // total_weight
        distributions.append(amount)
        distributed += amount
    return distributions


def test_tick_accrues_and_claims_full_round_payout(
    pasanaku_contract,
    usdc_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    deposit_all_obligors(
        pasanaku_contract,
        token_id,
        users,
        0,
        usdc_contract,
        owner,
        amount,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
    pasanaku_contract.tick(token_id)
    expected = amount * (PARTICIPANT_COUNT - 1)
    assert pasanaku_contract.pending_payout(token_id, 0) == expected

    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    balance = usdc_contract.balanceOf(recipient)
    with boa.env.prank(recipient):
        pasanaku_contract.claim_round_payout(token_id, 0)
    assert usdc_contract.balanceOf(recipient) == balance + expected


def test_miss_funds_recipient_and_moves_penalty_to_reserve(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    defaulter = next(user for user in users if user != recipient)
    before_locked = pasanaku_contract.locked_shares(token_id, defaulter)
    owner_balance = usdc_contract.balanceOf(owner)

    _deposit_except(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        recipient,
        defaulter,
        amount,
        token_id,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
    pasanaku_contract.tick(token_id)

    penalty = penalty_per_amount(amount)
    assert pasanaku_contract.pending_payout(token_id, 0) == amount * (
        PARTICIPANT_COUNT - 1
    )
    reserve = pasanaku_contract.pool_reserve_shares(token_id)
    after_locked = pasanaku_contract.locked_shares(token_id, defaulter)
    assert reserve == vault_contract.previewWithdraw(penalty)
    assert after_locked + reserve < before_locked
    assert (
        pasanaku_contract.locked_asset_basis(token_id, defaulter)
        == pledge(amount) - amount - penalty
    )
    assert usdc_contract.balanceOf(owner) == owner_balance


def test_last_tick_returns_principal_and_clears_locks(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    run_all_rounds(
        pasanaku_contract,
        token_id,
        users,
        usdc_contract,
        owner,
        amount,
    )
    state = pasanaku_contract.pasanaku(token_id)
    assert state.ended != 0
    assert pasanaku_contract.active_pasanaku_count() == 0
    assert pasanaku_contract.pool_reserve_shares(token_id) == 0
    for user in users:
        assert pasanaku_contract.locked_shares(token_id, user) == 0
        assert pasanaku_contract.locked_asset_basis(token_id, user) == 0
        assert pasanaku_contract.free_shares(user) > 0
    assert sum(pasanaku_contract.free_shares(u) for u in users) == (
        vault_contract.balanceOf(pasanaku_contract.address)
        - pasanaku_contract.eval("self._collected_fee_shares")
    )


def test_end_distributes_vault_yield_by_participant_position(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    with boa.env.prank(owner):
        pasanaku_contract.set_yield_fee(0)
    assert pasanaku_contract.pasanaku(token_id).yield_fee == MAX_YIELD_FEE
    participants = pasanaku_contract.pasanaku(token_id).participants
    initial_free = [
        pasanaku_contract.free_shares(participant) for participant in participants
    ]
    donate_yield(
        vault_contract,
        usdc_contract,
        owner,
        pledge(amount),
    )
    run_all_rounds(
        pasanaku_contract,
        token_id,
        users,
        usdc_contract,
        owner,
        amount,
    )
    balances = [
        pasanaku_contract.free_shares(participant) for participant in participants
    ]
    principal_shares = vault_contract.previewWithdraw(pledge(amount))
    fee_shares = pasanaku_contract.eval("self._collected_fee_shares")
    distributable_yield = (
        sum(balances) - sum(initial_free) - principal_shares * PARTICIPANT_COUNT
    )
    expected_yield = _weighted_distributions(
        distributable_yield,
        PARTICIPANT_COUNT,
    )
    assert balances == [
        free + principal_shares + distribution
        for free, distribution in zip(initial_free, expected_yield)
    ]
    assert balances == sorted(balances)
    assert len(set(balances)) == PARTICIPANT_COUNT
    assert sum(balances) + fee_shares == vault_contract.balanceOf(
        pasanaku_contract.address
    )


def test_end_accrues_yield_fee_shares_until_owner_collects(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    participants = pasanaku_contract.pasanaku(token_id).participants
    initial_free = [
        pasanaku_contract.free_shares(participant) for participant in participants
    ]
    donate_yield(
        vault_contract,
        usdc_contract,
        owner,
        pledge(amount),
    )

    contract_shares = vault_contract.balanceOf(pasanaku_contract.address)
    owner_balance = usdc_contract.balanceOf(owner)

    run_all_rounds(
        pasanaku_contract,
        token_id,
        users,
        usdc_contract,
        owner,
        amount,
    )

    balances = [
        pasanaku_contract.free_shares(participant) for participant in participants
    ]
    principal_shares = vault_contract.previewWithdraw(pledge(amount))
    fee_shares = pasanaku_contract.eval("self._collected_fee_shares")
    distributable_yield = (
        contract_shares
        - sum(initial_free)
        - principal_shares * PARTICIPANT_COUNT
        - fee_shares
    )
    expected_yield = _weighted_distributions(
        distributable_yield,
        PARTICIPANT_COUNT,
    )
    expected_fee_assets = vault_contract.previewRedeem(fee_shares)
    assert usdc_contract.balanceOf(owner) == owner_balance
    assert vault_contract.balanceOf(pasanaku_contract.address) == contract_shares
    assert pasanaku_contract.eval("self._collected_fee_shares") == fee_shares
    assert balances == [
        free + principal_shares + distribution
        for free, distribution in zip(initial_free, expected_yield)
    ]
    assert sum(balances) + fee_shares == contract_shares

    pasanaku_contract.collect_yield_fees()

    assert usdc_contract.balanceOf(owner) == (owner_balance + expected_fee_assets)
    assert vault_contract.balanceOf(pasanaku_contract.address) == (
        contract_shares - fee_shares
    )
    assert pasanaku_contract.eval("self._collected_fee_shares") == 0
    with boa.reverts(dev="no yield fees"):
        pasanaku_contract.collect_yield_fees()


def test_renouncing_ownership_does_not_block_final_settlement(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    donate_yield(
        vault_contract,
        usdc_contract,
        owner,
        pledge(amount),
    )
    with boa.env.prank(owner):
        pasanaku_contract.renounce_ownership()

    run_all_rounds(
        pasanaku_contract,
        token_id,
        users,
        usdc_contract,
        owner,
        amount,
    )

    assert pasanaku_contract.pasanaku(token_id).ended != 0
    assert pasanaku_contract.eval("self._collected_fee_shares") > 0


def test_reserve_covers_vault_loss_before_surplus_distribution(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    participants = pasanaku_contract.pasanaku(token_id).participants
    _deposit_except(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        participants[0],
        participants[1],
        amount,
        token_id,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
    pasanaku_contract.tick(token_id)
    reserve = pasanaku_contract.pool_reserve_shares(token_id)
    assert reserve > 0

    with boa.env.prank(owner):
        vault_contract.remove_assets(owner, penalty_per_amount(amount) // 2)

    for round_idx in range(1, PARTICIPANT_COUNT):
        deposit_all_obligors(
            pasanaku_contract,
            token_id,
            users,
            round_idx,
            usdc_contract,
            owner,
            amount,
        )
        boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
        pasanaku_contract.tick(token_id)

    assert pasanaku_contract.pool_reserve_shares(token_id) == 0
    assert sum(
        pasanaku_contract.free_shares(u) for u in users
    ) + pasanaku_contract.eval(
        "self._collected_fee_shares"
    ) == vault_contract.balanceOf(pasanaku_contract.address)
    for user in users:
        assert pasanaku_contract.locked_shares(token_id, user) == 0


def test_end_allocates_small_reserve_cumulatively_across_shortfalls(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    users,
):
    amount = 10_000
    token_id = create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        amount,
        PARTICIPANT_COUNT,
    )
    participants = pasanaku_contract.pasanaku(token_id).participants
    recipient = participants[0]
    defaulter = participants[1]
    _deposit_except(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        recipient,
        defaulter,
        amount,
        token_id,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
    pasanaku_contract.tick(token_id)
    assert pasanaku_contract.pool_reserve_shares(token_id) > 0

    with boa.env.prank(owner):
        vault_contract.remove_assets(owner, 1)

    for round_idx in range(1, PARTICIPANT_COUNT - 1):
        deposit_all_obligors(
            pasanaku_contract,
            token_id,
            users,
            round_idx,
            usdc_contract,
            owner,
            amount,
        )
        boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
        pasanaku_contract.tick(token_id)

    deposit_all_obligors(
        pasanaku_contract,
        token_id,
        users,
        PARTICIPANT_COUNT - 1,
        usdc_contract,
        owner,
        amount,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
    pasanaku_contract.tick(token_id)

    assert pasanaku_contract.pasanaku(token_id).ended != 0
    assert pasanaku_contract.pool_reserve_shares(token_id) == 0
    assert all(
        pasanaku_contract.locked_shares(token_id, participant) == 0
        for participant in participants
    )
    assert sum(
        pasanaku_contract.free_shares(participant) for participant in participants
    ) + pasanaku_contract.eval(
        "self._collected_fee_shares"
    ) == vault_contract.balanceOf(pasanaku_contract.address)


def test_miss_uses_combined_withdraw_preview(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    defaulter = next(user for user in users if user != recipient)
    donate_yield(
        vault_contract,
        usdc_contract,
        owner,
        amount // 3,
    )
    penalty = penalty_per_amount(amount)
    before_locked = pasanaku_contract.locked_shares(token_id, defaulter)

    _deposit_except(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        recipient,
        defaulter,
        amount,
        token_id,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
    needed_shares = vault_contract.previewWithdraw(amount + penalty)
    principal_shares = vault_contract.previewWithdraw(amount)
    explicit_penalty_shares = vault_contract.previewWithdraw(penalty)
    expected_penalty_shares = max(
        needed_shares - principal_shares,
        explicit_penalty_shares,
    )
    pasanaku_contract.tick(token_id)

    after_locked = pasanaku_contract.locked_shares(token_id, defaulter)
    reserve = pasanaku_contract.pool_reserve_shares(token_id)
    assert after_locked == before_locked - principal_shares - expected_penalty_shares
    assert reserve == expected_penalty_shares


def test_miss_reserves_penalty_when_combined_preview_gap_is_zero(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    defaulter = next(user for user in users if user != recipient)
    penalty = penalty_per_amount(amount)
    supply = vault_contract.totalSupply()
    target_assets = supply * 999_999
    donation = target_assets - vault_contract.totalAssets()
    with boa.env.prank(owner):
        usdc_contract.mint(owner, donation)
    donate_yield(
        vault_contract,
        usdc_contract,
        owner,
        donation,
    )

    before_locked = pasanaku_contract.locked_shares(token_id, defaulter)

    _deposit_except(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        recipient,
        defaulter,
        amount,
        token_id,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
    principal_shares = vault_contract.previewWithdraw(amount)
    needed_shares = vault_contract.previewWithdraw(amount + penalty)
    explicit_penalty_shares = vault_contract.previewWithdraw(penalty)
    assert needed_shares == principal_shares
    assert explicit_penalty_shares > 0
    pasanaku_contract.tick(token_id)

    assert pasanaku_contract.pool_reserve_shares(token_id) == explicit_penalty_shares
    assert (
        pasanaku_contract.locked_shares(token_id, defaulter)
        == before_locked - principal_shares - explicit_penalty_shares
    )
    assert (
        pasanaku_contract.locked_asset_basis(token_id, defaulter)
        == pledge(amount) - amount - penalty
    )


def test_miss_reserves_remaining_tip_when_principal_is_still_covered(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    defaulter = next(user for user in users if user != recipient)
    penalty = penalty_per_amount(amount)
    before_locked = pasanaku_contract.locked_shares(token_id, defaulter)

    _deposit_except(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        recipient,
        defaulter,
        amount,
        token_id,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
    supply = vault_contract.totalSupply()
    target_assets = (
        (amount + penalty // 2) * supply + before_locked - 1
    ) // before_locked
    with boa.env.prank(owner):
        vault_contract.remove_assets(
            owner, vault_contract.totalAssets() - target_assets
        )

    principal_shares = vault_contract.previewWithdraw(amount)
    needed_shares = vault_contract.previewWithdraw(amount + penalty)
    assert principal_shares <= before_locked < needed_shares
    remaining_tip_shares = before_locked - principal_shares

    pasanaku_contract.tick(token_id)

    assert pasanaku_contract.pending_payout(token_id, 0) == amount * (
        PARTICIPANT_COUNT - 1
    )
    assert pasanaku_contract.locked_shares(token_id, defaulter) == 0
    assert pasanaku_contract.pool_reserve_shares(token_id) == remaining_tip_shares
    assert pasanaku_contract.locked_asset_basis(token_id, defaulter) == 0


def test_end_does_not_fee_skim_leftover_miss_penalty_reserve(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    participants = pasanaku_contract.pasanaku(token_id).participants
    recipient = participants[0]
    defaulter = next(user for user in users if user != recipient)

    _deposit_except(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        recipient,
        defaulter,
        amount,
        token_id,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
    pasanaku_contract.tick(token_id)
    assert pasanaku_contract.pool_reserve_shares(token_id) > 0

    for round_idx in range(1, PARTICIPANT_COUNT):
        deposit_all_obligors(
            pasanaku_contract,
            token_id,
            users,
            round_idx,
            usdc_contract,
            owner,
            amount,
        )
        boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
        pasanaku_contract.tick(token_id)

    assert pasanaku_contract.pasanaku(token_id).ended != 0
    assert pasanaku_contract.pool_reserve_shares(token_id) == 0
    assert pasanaku_contract.eval("self._collected_fee_shares") == 0
    assert sum(
        pasanaku_contract.free_shares(user) for user in users
    ) == vault_contract.balanceOf(pasanaku_contract.address)


def test_underwater_miss_settles_partial_payout_and_pool_can_finish(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    defaulter = next(user for user in users if user != recipient)
    before_locked = pasanaku_contract.locked_shares(token_id, defaulter)

    _deposit_except(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        recipient,
        defaulter,
        amount,
        token_id,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
    with boa.env.prank(owner):
        vault_contract.remove_assets(owner, vault_contract.totalAssets() * 9 // 10)
    recovered_assets = vault_contract.previewRedeem(before_locked)

    pasanaku_contract.tick(token_id)

    expected_payout = amount * (PARTICIPANT_COUNT - 2) + recovered_assets
    assert pasanaku_contract.pending_payout(token_id, 0) == expected_payout
    assert pasanaku_contract.pool_escrow(token_id) == 0
    assert pasanaku_contract.locked_shares(token_id, defaulter) == 0
    assert pasanaku_contract.locked_asset_basis(token_id, defaulter) == 0

    for round_idx in range(1, PARTICIPANT_COUNT):
        deposit_all_obligors(
            pasanaku_contract,
            token_id,
            users,
            round_idx,
            usdc_contract,
            owner,
            amount,
        )
        boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
        pasanaku_contract.tick(token_id)

    assert pasanaku_contract.pasanaku(token_id).ended != 0


def test_empty_vault_miss_does_not_block_pool_completion(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    defaulter = next(user for user in users if user != recipient)

    _deposit_except(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        recipient,
        defaulter,
        amount,
        token_id,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
    with boa.env.prank(owner):
        vault_contract.remove_assets(owner, vault_contract.totalAssets())
    recovered_assets = vault_contract.previewRedeem(
        pasanaku_contract.locked_shares(token_id, defaulter)
    )

    pasanaku_contract.tick(token_id)

    escrow_payout = amount * (PARTICIPANT_COUNT - 2)
    payout = pasanaku_contract.pending_payout(token_id, 0)
    assert (
        escrow_payout <= payout <= (escrow_payout + recovered_assets * 101 // 100 + 1)
    )
    assert pasanaku_contract.locked_shares(token_id, defaulter) == 0
    assert pasanaku_contract.locked_asset_basis(token_id, defaulter) == 0

    for round_idx in range(1, PARTICIPANT_COUNT):
        deposit_all_obligors(
            pasanaku_contract,
            token_id,
            users,
            round_idx,
            usdc_contract,
            owner,
            amount,
        )
        boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
        pasanaku_contract.tick(token_id)

    assert pasanaku_contract.pasanaku(token_id).ended != 0


def test_tick_too_early_reverts(pasanaku_contract, started_pasanaku):
    with boa.reverts(dev="not enough time passed"):
        pasanaku_contract.tick(started_pasanaku["token_id"])


def test_throttled_vault_liquidity_reverts_tick_without_wiping_collateral(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    defaulter = next(user for user in users if user != recipient)

    _deposit_except(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        recipient,
        defaulter,
        amount,
        token_id,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)

    before_locked = pasanaku_contract.locked_shares(token_id, defaulter)
    before_basis = pasanaku_contract.locked_asset_basis(token_id, defaulter)
    before_index = pasanaku_contract.pasanaku(token_id).index
    before_escrow = pasanaku_contract.pool_escrow(token_id)

    with boa.env.prank(owner):
        vault_contract.set_withdraw_limit(amount - 1)

    with boa.reverts(dev="exceed withdraw limit"):
        pasanaku_contract.tick(token_id)

    assert pasanaku_contract.locked_shares(token_id, defaulter) == before_locked
    assert pasanaku_contract.locked_asset_basis(token_id, defaulter) == before_basis
    assert pasanaku_contract.pasanaku(token_id).index == before_index
    assert pasanaku_contract.pool_escrow(token_id) == before_escrow
    assert pasanaku_contract.pending_payout(token_id, 0) == 0
    assert pasanaku_contract.pool_reserve_shares(token_id) == 0


def test_tick_succeeds_after_vault_liquidity_limit_cleared(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    defaulter = next(user for user in users if user != recipient)

    _deposit_except(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        recipient,
        defaulter,
        amount,
        token_id,
    )
    boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)

    with boa.env.prank(owner):
        vault_contract.set_withdraw_limit(amount - 1)

    with boa.reverts(dev="exceed withdraw limit"):
        pasanaku_contract.tick(token_id)

    with boa.env.prank(owner):
        vault_contract.set_withdraw_limit(2**256 - 1)

    pasanaku_contract.tick(token_id)

    assert pasanaku_contract.pasanaku(token_id).index == 1
    assert pasanaku_contract.pending_payout(token_id, 0) == amount * (
        PARTICIPANT_COUNT - 1
    )
    assert pasanaku_contract.locked_asset_basis(token_id, defaulter) == pledge(
        amount
    ) - amount - penalty_per_amount(amount)
    assert pasanaku_contract.pool_reserve_shares(token_id) > 0
