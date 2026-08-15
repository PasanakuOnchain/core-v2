import boa
import pytest

from tests.utils.constants import (
    DAYS_3,
    DAYS_7,
    INVALID_PARTICIPANT_COUNTS,
    PASANAKU_AMOUNT_RAW,
    PARTICIPANT_COUNTS,
)
from tests.utils.helpers import (
    create_and_join_all,
    create_pasanaku,
    donate_yield,
    fund_collateral_for_users,
    generate_users,
    pledge,
    run_all_rounds,
)


def test_deploy_uses_one_asset_and_vault(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
):
    assert pasanaku_contract._immutables._ASSET == usdc_contract.address
    assert pasanaku_contract._immutables._VAULT == vault_contract.address
    assert pasanaku_contract.asset() == pasanaku_contract._immutables._ASSET
    assert pasanaku_contract.vault() == pasanaku_contract._immutables._VAULT


@pytest.mark.parametrize("participant_count", INVALID_PARTICIPANT_COUNTS)
def test_create_rejects_unsupported_participant_count(
    pasanaku_contract,
    users,
    participant_count,
):
    with boa.reverts(dev="invalid participant count"):
        with boa.env.prank(users[0]):
            pasanaku_contract.create_pasanaku(
                PASANAKU_AMOUNT_RAW,
                participant_count,
            )


@pytest.mark.parametrize("participant_count", PARTICIPANT_COUNTS)
def test_pasanaku_starts_at_configured_size(
    pasanaku_contract,
    usdc_contract,
    owner,
    participant_count,
):
    participants = generate_users(participant_count)
    token_id = create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        participants,
        PASANAKU_AMOUNT_RAW,
        participant_count,
    )
    state = pasanaku_contract.pasanaku(token_id)
    assert state.participant_count == participant_count
    assert len(state.participants) == participant_count
    assert set(state.participants) == set(participants)
    assert state.started != 0


@pytest.mark.parametrize("participant_count", PARTICIPANT_COUNTS)
def test_all_rounds_completes_for_supported_sizes(
    pasanaku_contract,
    usdc_contract,
    owner,
    participant_count,
):
    participants = generate_users(participant_count)
    token_id = create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        participants,
        PASANAKU_AMOUNT_RAW,
        participant_count,
    )
    run_all_rounds(
        pasanaku_contract,
        token_id,
        participants,
        usdc_contract,
        owner,
        PASANAKU_AMOUNT_RAW,
    )
    state = pasanaku_contract.pasanaku(token_id)
    assert state.ended != 0
    assert state.index == participant_count


def test_create_and_join_lock_shares(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    users,
):
    needed = vault_contract.previewWithdraw(pledge(PASANAKU_AMOUNT_RAW, 6))
    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        users[:2],
        PASANAKU_AMOUNT_RAW,
        6,
    )
    with boa.env.prank(users[0]):
        token_id = create_pasanaku(
            pasanaku_contract,
            PASANAKU_AMOUNT_RAW,
            6,
        )
    with boa.env.prank(users[1]):
        pasanaku_contract.join_pasanaku(token_id)
    assert pasanaku_contract.locked_shares(token_id, users[0]) == needed
    assert pasanaku_contract.locked_shares(token_id, users[1]) == needed


def test_pre_start_yield_remains_with_depositor(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    users,
):
    amount = PASANAKU_AMOUNT_RAW
    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        users[:5],
        amount,
        6,
    )
    with boa.env.prank(users[0]):
        token_id = create_pasanaku(pasanaku_contract, amount, 6)
    for user in users[1:5]:
        with boa.env.prank(user):
            pasanaku_contract.join_pasanaku(token_id)

    donate_yield(
        vault_contract,
        usdc_contract,
        owner,
        pledge(amount, 6) // 10,
    )
    last_deposit = pledge(amount, 6) + 2
    with boa.env.prank(owner):
        usdc_contract.mint(users[5], last_deposit)
    with boa.env.prank(users[5]):
        usdc_contract.approve(pasanaku_contract.address, last_deposit)
        pasanaku_contract.deposit(last_deposit, users[5])
    with boa.env.prank(users[5]):
        pasanaku_contract.join_pasanaku(token_id)

    assert pasanaku_contract.free_shares(users[0]) > 0
    for user in users:
        assert pasanaku_contract.locked_asset_basis(token_id, user) == pledge(amount, 6)


def test_leave_stale_pool_returns_locked_shares(
    pasanaku_contract,
    usdc_contract,
    owner,
    users,
):
    with boa.env.prank(owner):
        pasanaku_contract.set_stale_time(DAYS_3)
    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        users[:2],
        PASANAKU_AMOUNT_RAW,
        6,
    )
    with boa.env.prank(users[0]):
        token_id = create_pasanaku(
            pasanaku_contract,
            PASANAKU_AMOUNT_RAW,
            6,
        )
    with boa.env.prank(users[1]):
        pasanaku_contract.join_pasanaku(token_id)
    locked = pasanaku_contract.locked_shares(token_id, users[1])
    free_before_leave = pasanaku_contract.free_shares(users[1])

    boa.env.time_travel(seconds=DAYS_3)
    with boa.env.prank(users[1]):
        pasanaku_contract.leave_pasanaku(token_id)

    assert pasanaku_contract.locked_shares(token_id, users[1]) == 0
    assert pasanaku_contract.free_shares(users[1]) == free_before_leave + locked


def test_join_stale_pool_reverts_and_leave_still_works(
    pasanaku_contract,
    usdc_contract,
    owner,
    users,
):
    with boa.env.prank(owner):
        pasanaku_contract.set_stale_time(DAYS_3)
    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        users[:3],
        PASANAKU_AMOUNT_RAW,
        6,
    )
    with boa.env.prank(users[0]):
        token_id = create_pasanaku(
            pasanaku_contract,
            PASANAKU_AMOUNT_RAW,
            6,
        )
    with boa.env.prank(users[1]):
        pasanaku_contract.join_pasanaku(token_id)

    boa.env.time_travel(seconds=DAYS_3)
    with boa.reverts(dev="pasanaku is stale"):
        with boa.env.prank(users[2]):
            pasanaku_contract.join_pasanaku(token_id)
    with boa.env.prank(users[1]):
        pasanaku_contract.leave_pasanaku(token_id)

    assert users[1] not in pasanaku_contract.pasanaku(token_id).participants


def test_stale_time_is_snapshotted_per_pool(
    pasanaku_contract,
    usdc_contract,
    owner,
    users,
):
    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        users[:2],
        PASANAKU_AMOUNT_RAW,
        6,
    )
    with boa.env.prank(users[0]):
        original_token_id = create_pasanaku(
            pasanaku_contract,
            PASANAKU_AMOUNT_RAW,
            6,
        )
    with boa.env.prank(users[1]):
        pasanaku_contract.join_pasanaku(original_token_id)

    with boa.env.prank(owner):
        pasanaku_contract.set_stale_time(DAYS_3)
    assert pasanaku_contract.pasanaku(original_token_id).stale_time == DAYS_7

    boa.env.time_travel(seconds=DAYS_3)
    with boa.reverts(dev="pasanaku is not stale"):
        with boa.env.prank(users[1]):
            pasanaku_contract.leave_pasanaku(original_token_id)

    boa.env.time_travel(seconds=DAYS_7 - DAYS_3)
    with boa.env.prank(users[1]):
        pasanaku_contract.leave_pasanaku(original_token_id)

    with boa.env.prank(users[1]):
        new_token_id = create_pasanaku(
            pasanaku_contract,
            PASANAKU_AMOUNT_RAW,
            6,
        )
    assert pasanaku_contract.pasanaku(new_token_id).stale_time == DAYS_3
