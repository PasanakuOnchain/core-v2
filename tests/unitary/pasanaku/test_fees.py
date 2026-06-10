import boa

from tests.utils.constants import MAX_FEE, MIN_FEE, PASANAKU_AMOUNT_RAW
from tests.utils.helpers import create_pasanaku, fund_collateral_for_users

SAMPLE_FEE = 10**12  # 0.000001 ether


def _reset_fee(pasanaku_contract, owner):
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(MIN_FEE)


def test_fee_defaults_to_zero(pasanaku_contract):
    assert pasanaku_contract.fee() == MIN_FEE


def test_set_fee_owner_updates(pasanaku_contract, owner):
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(SAMPLE_FEE)

    fee_logs = [
        log for log in pasanaku_contract.get_logs() if type(log).__name__ == "FeeSet"
    ]
    assert len(fee_logs) == 1
    assert fee_logs[0].fee == SAMPLE_FEE
    assert pasanaku_contract.fee() == SAMPLE_FEE
    _reset_fee(pasanaku_contract, owner)


def test_set_fee_non_owner_reverts(pasanaku_contract, alice):
    with boa.reverts():
        with boa.env.prank(alice):
            pasanaku_contract.set_fee(SAMPLE_FEE)


def test_set_fee_above_max_reverts(pasanaku_contract, owner):
    with boa.reverts(dev="fee is out of range"):
        with boa.env.prank(owner):
            pasanaku_contract.set_fee(MAX_FEE + 1)


def test_set_fee_at_bounds(pasanaku_contract, owner):
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(MIN_FEE)
    assert pasanaku_contract.fee() == MIN_FEE

    with boa.env.prank(owner):
        pasanaku_contract.set_fee(MAX_FEE)
    assert pasanaku_contract.fee() == MAX_FEE

    _reset_fee(pasanaku_contract, owner)


def test_create_succeeds_with_zero_fee_no_value(
    pasanaku_contract, owner, usdc_contract, users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [users[0]], amount_raw
    )
    with boa.env.prank(users[0]):
        token_id = create_pasanaku(
            pasanaku_contract, usdc_contract.address, amount_raw, value=0
        )
    assert token_id == 0


def test_create_insufficient_fee_reverts(
    pasanaku_contract, owner, usdc_contract, users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    creator = users[0]
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(SAMPLE_FEE)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [creator], amount_raw
    )
    with boa.reverts(dev="insufficient fee"):
        with boa.env.prank(creator):
            pasanaku_contract.create_pasanaku(
                usdc_contract.address, amount_raw, value=SAMPLE_FEE - 1
            )
    _reset_fee(pasanaku_contract, owner)


def test_create_accepts_exact_fee(pasanaku_contract, owner, usdc_contract, users):
    amount_raw = PASANAKU_AMOUNT_RAW
    creator = users[0]
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(SAMPLE_FEE)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [creator], amount_raw
    )

    contract_balance_before = boa.env.get_balance(pasanaku_contract.address)
    with boa.env.prank(creator):
        create_pasanaku(
            pasanaku_contract,
            usdc_contract.address,
            amount_raw,
            value=SAMPLE_FEE,
        )

    assert (
        boa.env.get_balance(pasanaku_contract.address)
        == contract_balance_before + SAMPLE_FEE
    )
    _reset_fee(pasanaku_contract, owner)


def test_create_accepts_overpayment(pasanaku_contract, owner, usdc_contract, users):
    amount_raw = PASANAKU_AMOUNT_RAW
    creator = users[0]
    overpay = SAMPLE_FEE * 2
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(SAMPLE_FEE)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [creator], amount_raw
    )

    contract_balance_before = boa.env.get_balance(pasanaku_contract.address)
    with boa.env.prank(creator):
        create_pasanaku(
            pasanaku_contract,
            usdc_contract.address,
            amount_raw,
            value=overpay,
        )

    assert (
        boa.env.get_balance(pasanaku_contract.address)
        == contract_balance_before + overpay
    )
    _reset_fee(pasanaku_contract, owner)


def test_create_after_fee_update(pasanaku_contract, owner, usdc_contract, users):
    amount_raw = PASANAKU_AMOUNT_RAW
    creator = users[0]
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(SAMPLE_FEE)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [creator], amount_raw
    )
    with boa.env.prank(creator):
        token_id = create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)
    assert token_id >= 0
    _reset_fee(pasanaku_contract, owner)


def test_collect_fees_sweeps_to_owner(pasanaku_contract, owner, usdc_contract, users):
    amount_raw = PASANAKU_AMOUNT_RAW
    creator = users[0]
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(SAMPLE_FEE)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [creator], amount_raw
    )
    with boa.env.prank(creator):
        create_pasanaku(
            pasanaku_contract,
            usdc_contract.address,
            amount_raw,
            value=SAMPLE_FEE,
        )

    owner_balance_before = boa.env.get_balance(owner)
    pasanaku_contract.collect_fees()

    assert boa.env.get_balance(pasanaku_contract.address) == 0
    assert boa.env.get_balance(owner) == owner_balance_before + SAMPLE_FEE
    _reset_fee(pasanaku_contract, owner)


def test_collect_fees_emits_event(pasanaku_contract, owner, usdc_contract, users):
    amount_raw = PASANAKU_AMOUNT_RAW
    creator = users[0]
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(SAMPLE_FEE)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [creator], amount_raw
    )
    with boa.env.prank(creator):
        create_pasanaku(
            pasanaku_contract,
            usdc_contract.address,
            amount_raw,
            value=SAMPLE_FEE,
        )

    pasanaku_contract.collect_fees()
    collected = [
        log
        for log in pasanaku_contract.get_logs()
        if type(log).__name__ == "FeesCollected"
    ]
    assert len(collected) == 1
    assert collected[0].target == owner
    _reset_fee(pasanaku_contract, owner)


def test_collect_fees_permissionless(
    pasanaku_contract, owner, alice, usdc_contract, users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    creator = users[0]
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(SAMPLE_FEE)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [creator], amount_raw
    )
    with boa.env.prank(creator):
        create_pasanaku(
            pasanaku_contract,
            usdc_contract.address,
            amount_raw,
            value=SAMPLE_FEE,
        )

    owner_balance_before = boa.env.get_balance(owner)
    with boa.env.prank(alice):
        pasanaku_contract.collect_fees()

    assert boa.env.get_balance(owner) == owner_balance_before + SAMPLE_FEE
    _reset_fee(pasanaku_contract, owner)
