import boa

from tests.utils.constants import DAYS_40, PARTICIPANT_COUNT
from tests.utils.helpers import (
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
            pasanaku.deposit_to_pasanaku(amount, token_id)


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
    boa.env.time_travel(seconds=DAYS_40)
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
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    defaulter = next(user for user in users if user != recipient)
    before_locked = pasanaku_contract.locked_shares(
        token_id, defaulter
    )
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
    boa.env.time_travel(seconds=DAYS_40)
    pasanaku_contract.tick(token_id)

    penalty = penalty_per_amount(amount)
    assert pasanaku_contract.pending_payout(token_id, 0) == amount * (
        PARTICIPANT_COUNT - 1
    )
    assert pasanaku_contract.pool_reserve_shares(token_id) == penalty
    assert pasanaku_contract.locked_shares(
        token_id, defaulter
    ) == before_locked - amount - penalty
    assert pasanaku_contract.locked_asset_basis(
        token_id, defaulter
    ) == pledge(amount) - amount - penalty
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
        assert pasanaku_contract.free_shares(user) == pledge(amount)
    assert sum(pasanaku_contract.free_shares(u) for u in users) == (
        vault_contract.balanceOf(pasanaku_contract.address)
    )


def test_end_distributes_vault_yield_equally(
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
    principal_shares = vault_contract.previewWithdraw(pledge(amount))
    run_all_rounds(
        pasanaku_contract,
        token_id,
        users,
        usdc_contract,
        owner,
        amount,
    )
    balances = [pasanaku_contract.free_shares(user) for user in users]
    assert len(set(balances)) == 1
    assert balances[0] > principal_shares


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
    boa.env.time_travel(seconds=DAYS_40)
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
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(token_id)

    assert pasanaku_contract.pool_reserve_shares(token_id) == 0
    assert sum(pasanaku_contract.free_shares(u) for u in users) == (
        vault_contract.balanceOf(pasanaku_contract.address)
    )
    for user in users:
        assert pasanaku_contract.locked_shares(token_id, user) == 0


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
    needed_shares = vault_contract.previewWithdraw(amount + penalty)
    principal_shares = vault_contract.previewWithdraw(amount)
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
    boa.env.time_travel(seconds=DAYS_40)
    pasanaku_contract.tick(token_id)

    assert pasanaku_contract.locked_shares(
        token_id, defaulter
    ) == before_locked - needed_shares
    assert pasanaku_contract.pool_reserve_shares(
        token_id
    ) == needed_shares - principal_shares


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
    with boa.env.prank(owner):
        vault_contract.remove_assets(
            owner, vault_contract.totalAssets() * 9 // 10
        )
    recovered_assets = vault_contract.previewRedeem(before_locked)

    boa.env.time_travel(seconds=DAYS_40)
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
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(token_id)

    assert pasanaku_contract.pasanaku(token_id).ended != 0


def test_tick_too_early_reverts(pasanaku_contract, started_pasanaku):
    with boa.reverts(dev="not enough time passed"):
        pasanaku_contract.tick(started_pasanaku["token_id"])
