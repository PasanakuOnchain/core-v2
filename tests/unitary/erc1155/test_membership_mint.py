import boa

from tests.utils.constants import PARTICIPANT_COUNT, PASANAKU_AMOUNT_RAW, TOKEN_AMOUNT
from tests.utils.helpers import create_and_join_all, fund_collateral_for_users
from tests.mocks import noop_contract


def test_membership_not_minted_before_start(pasanaku_contract, owner, usdc_contract, users):
    """Pre-start: no balances, no supply, token does not exist."""
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, users[:2], PASANAKU_AMOUNT_RAW
    )
    with boa.env.prank(users[0]):
        token_id = pasanaku_contract.create_pasanaku(
            usdc_contract.address, PASANAKU_AMOUNT_RAW
        )

    assert pasanaku_contract.total_supply(token_id) == 0
    assert pasanaku_contract.exists(token_id) is False
    for u in users[:2]:
        assert pasanaku_contract.balanceOf(u, token_id) == 0


def test_membership_mint_on_start_updates_supply_and_balances(
    pasanaku_contract, owner, usdc_contract, users
):
    """Regression: _mint_membership_token increments total_supply and balanceOf."""
    create_and_join_all(
        pasanaku_contract, usdc_contract, owner, users, PASANAKU_AMOUNT_RAW
    )
    token_id = 0

    assert pasanaku_contract.total_supply(token_id) == PARTICIPANT_COUNT * TOKEN_AMOUNT
    assert pasanaku_contract.exists(token_id) is True
    for u in users:
        assert pasanaku_contract.balanceOf(u, token_id) == TOKEN_AMOUNT


def test_membership_mint_emits_transfer_single_logs(
    pasanaku_contract, owner, usdc_contract, users
):
    create_and_join_all(
        pasanaku_contract, usdc_contract, owner, users, PASANAKU_AMOUNT_RAW
    )
    token_id = 0

    transfer_logs = [
        log for log in pasanaku_contract.get_logs() if type(log).__name__ == "TransferSingle"
    ]
    assert len(transfer_logs) == PARTICIPANT_COUNT

    recipients = {log._3 for log in transfer_logs}
    assert recipients == set(users)
    for log in transfer_logs:
        assert log._2 == "0x0000000000000000000000000000000000000000"
        assert log._4 == token_id
        assert log._5 == TOKEN_AMOUNT


def test_contract_wallet_participant_receives_membership(
    pasanaku_contract, owner, usdc_contract, users
):
    noop = noop_contract.deploy()
    participants = users[: PARTICIPANT_COUNT - 1] + [noop.address]
    create_and_join_all(
        pasanaku_contract, usdc_contract, owner, participants, PASANAKU_AMOUNT_RAW
    )
    tid = 0
    assert pasanaku_contract.balanceOf(noop.address, tid) == TOKEN_AMOUNT
    assert pasanaku_contract.total_supply(tid) == PARTICIPANT_COUNT
