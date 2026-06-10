import boa

from tests.utils.constants import PASANAKU_AMOUNT_RAW
from tests.utils.helpers import fund_collateral_for_users


def test_recipient_cannot_deposit(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    recipient = started_pasanaku["users"][0]
    with boa.env.prank(owner):
        usdc_contract.mint(recipient, amount_raw)
    with boa.env.prank(recipient):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        with boa.reverts(dev="active participant cannot deposit # nosplit"):
            pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)


def test_duplicate_deposit_same_round_reverts(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    payer = started_pasanaku["users"][1]
    extra = amount_raw * 2
    with boa.env.prank(owner):
        usdc_contract.mint(payer, extra)
    with boa.env.prank(payer):
        usdc_contract.approve(pasanaku_contract.address, extra)
        pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)
        with boa.reverts(dev="account already deposited # nosplit"):
            pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)


def test_deposit_wrong_amount_reverts(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    payer = started_pasanaku["users"][1]
    with boa.env.prank(owner):
        usdc_contract.mint(payer, amount_raw)
    with boa.env.prank(payer):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        with boa.reverts(dev="invalid deposit amount"):
            pasanaku_contract.deposit_to_pasanaku(amount_raw - 1, tid)


def test_deposit_increases_contract_escrow_balance(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    payer = started_pasanaku["users"][1]
    pre_escrow = usdc_contract.balanceOf(pasanaku_contract.address)

    with boa.env.prank(owner):
        usdc_contract.mint(payer, amount_raw)
    with boa.env.prank(payer):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)

    assert usdc_contract.balanceOf(pasanaku_contract.address) == pre_escrow + amount_raw


def test_deposited_for_pasanaku_flag(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    payer = started_pasanaku["users"][1]

    assert pasanaku_contract.deposited_for_pasanaku(tid, 0, payer) is False

    with boa.env.prank(owner):
        usdc_contract.mint(payer, amount_raw)
    with boa.env.prank(payer):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)

    assert pasanaku_contract.deposited_for_pasanaku(tid, 0, payer) is True
    assert pasanaku_contract.successful_obligated_deposits(tid, payer) == 1


def test_deposit_emits_event(pasanaku_contract, owner, usdc_contract, started_pasanaku):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    payer = started_pasanaku["users"][1]

    with boa.env.prank(owner):
        usdc_contract.mint(payer, amount_raw)
    with boa.env.prank(payer):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)

    deposited = [
        log for log in pasanaku_contract.get_logs() if type(log).__name__ == "PasanakuDeposited"
    ]
    assert len(deposited) == 1
    assert deposited[0].account == payer
    assert deposited[0].token_id == tid
    assert deposited[0].index == 0
    assert deposited[0].amount == amount_raw


def test_deposit_invalid_token_id_reverts(pasanaku_contract, started_pasanaku):
    amount_raw = started_pasanaku["amount_raw"]
    payer = started_pasanaku["users"][1]
    with boa.reverts(dev="invalid token id"):
        with boa.env.prank(payer):
            pasanaku_contract.deposit_to_pasanaku(amount_raw, 999)


def test_deposit_not_participant_reverts(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    outsider = boa.env.generate_address()
    with boa.env.prank(owner):
        usdc_contract.mint(outsider, amount_raw)
    with boa.env.prank(outsider):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        with boa.reverts(dev="account not in pasanaku # nosplit"):
            pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)


def test_deposit_before_start_reverts(
    pasanaku_contract, owner, usdc_contract, users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [users[0]], amount_raw
    )
    with boa.env.prank(users[0]):
        token_id = pasanaku_contract.create_pasanaku(usdc_contract.address, amount_raw)

    payer = users[0]
    with boa.env.prank(owner):
        usdc_contract.mint(payer, amount_raw)
    with boa.env.prank(payer):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        with boa.reverts(dev="pasanaku not started"):
            pasanaku_contract.deposit_to_pasanaku(amount_raw, token_id)


def test_successful_obligated_deposits_increments_per_round(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    payer = users[2]

    for round_idx in range(2):
        with boa.env.prank(owner):
            usdc_contract.mint(payer, amount_raw)
        with boa.env.prank(payer):
            usdc_contract.approve(pasanaku_contract.address, amount_raw)
            pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)
        assert pasanaku_contract.successful_obligated_deposits(tid, payer) == round_idx + 1
        if round_idx == 0:
            boa.env.time_travel(seconds=40 * 24 * 60 * 60)
            pasanaku_contract.tick(tid)
