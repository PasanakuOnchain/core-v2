import boa

from tests.utils.constants import (
    MAX_FEE,
    MAX_YIELD_FEE,
    PASANAKU_AMOUNT_RAW,
)
from tests.utils.helpers import create_pasanaku, fund_collateral_for_users


SAMPLE_FEE = 10**12
SAMPLE_YIELD_FEE = 100


def test_fee_defaults_to_constructor_value(pasanaku_contract):
    assert pasanaku_contract.fee() == 0


def test_yield_fee_defaults_to_constructor_value(pasanaku_contract):
    assert pasanaku_contract.yield_fee() == MAX_YIELD_FEE


def test_owner_can_update_fee(pasanaku_contract, owner):
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(SAMPLE_FEE)
    assert pasanaku_contract.fee() == SAMPLE_FEE


def test_owner_can_update_yield_fee(pasanaku_contract, owner):
    with boa.env.prank(owner):
        pasanaku_contract.set_yield_fee(SAMPLE_YIELD_FEE)
    assert pasanaku_contract.yield_fee() == SAMPLE_YIELD_FEE


def test_non_owner_cannot_update_fee(pasanaku_contract, alice):
    with boa.reverts():
        with boa.env.prank(alice):
            pasanaku_contract.set_fee(SAMPLE_FEE)


def test_non_owner_cannot_update_yield_fee(pasanaku_contract, alice):
    with boa.reverts():
        with boa.env.prank(alice):
            pasanaku_contract.set_yield_fee(SAMPLE_YIELD_FEE)


def test_fee_above_max_reverts(pasanaku_contract, owner):
    with boa.reverts(dev="fee is out of range"):
        with boa.env.prank(owner):
            pasanaku_contract.set_fee(MAX_FEE + 1)


def test_yield_fee_above_max_reverts(pasanaku_contract, owner):
    with boa.reverts(dev="fee is out of range"):
        with boa.env.prank(owner):
            pasanaku_contract.set_yield_fee(MAX_YIELD_FEE + 1)


def test_create_requires_configured_fee(
    pasanaku_contract,
    usdc_contract,
    owner,
    users,
):
    creator = users[0]
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(SAMPLE_FEE)
    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        [creator],
        PASANAKU_AMOUNT_RAW,
    )
    with boa.reverts(dev="insufficient fee"):
        with boa.env.prank(creator):
            pasanaku_contract.create_pasanaku(
                PASANAKU_AMOUNT_RAW,
                6,
                value=SAMPLE_FEE - 1,
            )


def test_collect_fees_sends_native_balance_to_owner(
    pasanaku_contract,
    usdc_contract,
    owner,
    users,
):
    creator = users[0]
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(SAMPLE_FEE)
    fund_collateral_for_users(
        pasanaku_contract,
        usdc_contract,
        owner,
        [creator],
        PASANAKU_AMOUNT_RAW,
    )
    with boa.env.prank(creator):
        create_pasanaku(
            pasanaku_contract,
            PASANAKU_AMOUNT_RAW,
            6,
            value=SAMPLE_FEE,
        )
    owner_balance = boa.env.get_balance(owner)
    pasanaku_contract.collect_fees()
    assert boa.env.get_balance(owner) == owner_balance + SAMPLE_FEE
