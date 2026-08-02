import boa

from src import Pasanaku as pasanaku
from tests.utils.constants import (
    BPS_PRECISION,
    MAX_FEE,
    MAX_YIELD_FEE,
    PASANAKU_AMOUNT_RAW,
    PARTICIPANT_COUNT,
)
from tests.utils.helpers import (
    create_pasanaku,
    donate_yield,
    fund_collateral_for_users,
    pledge,
    run_all_rounds,
)


SAMPLE_FEE = 10**12
SAMPLE_YIELD_FEE = 100
EXCESS_FEE = 10**14


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


def test_owner_can_set_fee_at_max(pasanaku_contract, owner):
    with boa.env.prank(owner):
        pasanaku_contract.set_fee(MAX_FEE)
    assert pasanaku_contract.fee() == MAX_FEE


def test_owner_can_set_yield_fee_at_max(pasanaku_contract, owner):
    with boa.env.prank(owner):
        pasanaku_contract.set_yield_fee(MAX_YIELD_FEE)
    assert pasanaku_contract.yield_fee() == MAX_YIELD_FEE


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


def test_constructor_fee_above_max_reverts(usdc_contract, vault_contract, owner):
    with boa.reverts(dev="fee is out of range"):
        with boa.env.prank(owner):
            pasanaku.deploy(
                usdc_contract.address,
                vault_contract.address,
                MAX_FEE + 1,
                0,
            )


def test_constructor_yield_fee_above_max_reverts(usdc_contract, vault_contract, owner):
    with boa.reverts(dev="yield fee is out of range"):
        with boa.env.prank(owner):
            pasanaku.deploy(
                usdc_contract.address,
                vault_contract.address,
                0,
                MAX_YIELD_FEE + 1,
            )


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
                PARTICIPANT_COUNT,
                value=SAMPLE_FEE - 1,
            )


def test_create_refunds_excess_fee_to_creator(
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
    creator_balance = boa.env.get_balance(creator)
    with boa.env.prank(creator):
        create_pasanaku(
            pasanaku_contract,
            PASANAKU_AMOUNT_RAW,
            PARTICIPANT_COUNT,
            value=SAMPLE_FEE + EXCESS_FEE,
        )
    assert boa.env.get_balance(creator) == creator_balance - SAMPLE_FEE
    assert boa.env.get_balance(pasanaku_contract.address) == SAMPLE_FEE


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
            PARTICIPANT_COUNT,
            value=SAMPLE_FEE,
        )
    owner_balance = boa.env.get_balance(owner)
    pasanaku_contract.collect_fees()
    assert boa.env.get_balance(owner) == owner_balance + SAMPLE_FEE


def test_collect_fees_when_empty_leaves_owner_balance(pasanaku_contract, owner):
    owner_balance = boa.env.get_balance(owner)
    pasanaku_contract.collect_fees()
    assert boa.env.get_balance(owner) == owner_balance
    assert boa.env.get_balance(pasanaku_contract.address) == 0


def test_end_yield_fee_matches_surplus_formula(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    started_pasanaku,
):
    """Money Flow: vault yield surplus → fee_shares = surplus * yield_fee // BPS."""
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    pool_yield_fee = pasanaku_contract.pasanaku(token_id).yield_fee
    assert pool_yield_fee == MAX_YIELD_FEE

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

    run_all_rounds(
        pasanaku_contract,
        token_id,
        users,
        usdc_contract,
        owner,
        amount,
    )

    principal_shares = vault_contract.previewWithdraw(pledge(amount))
    fee_shares = pasanaku_contract.eval("self._collected_fee_shares")
    yield_surplus = (
        contract_shares - sum(initial_free) - principal_shares * PARTICIPANT_COUNT
    )
    assert fee_shares == yield_surplus * pool_yield_fee // BPS_PRECISION
    assert fee_shares == (
        yield_surplus
        * pasanaku_contract._constants._MAX_YIELD_FEE
        // pasanaku_contract._constants._BPS_PRECISION
    )
