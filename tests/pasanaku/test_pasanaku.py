import boa
from hypothesis import HealthCheck, given, settings
from hypothesis.stateful import RuleBasedStateMachine, initialize, invariant, rule
import hypothesis.strategies as st
from src import Pasanaku as pasanaku
from tests.mocks import erc20_mock
from tests.utils.helpers import mint_token

USERS_COUNT = 3
MAX_AMOUNT = 10**12


def test_protocol_fee(pasanaku_contract):
    assert pasanaku_contract.protocolFee() == int(0.000075 * 10**18)


def test_deposit_collateral(pasanaku_contract, alice, owner, usdc_contract):
    amount = mint_token(owner, usdc_contract, alice, 10_000)

    assert usdc_contract.balanceOf(alice) == amount

    with boa.env.prank(alice):
        usdc_contract.approve(pasanaku_contract.address, amount)
        pasanaku_contract.addCollateral(usdc_contract.address, amount)

    assert pasanaku_contract.collateralReserves(usdc_contract.address) == amount
    assert pasanaku_contract.freeCollateral(alice, usdc_contract.address) == amount
    assert pasanaku_contract.lockedCollateral(alice, 0) == 0


def test_deposit_collateral_and_withdraw(
    pasanaku_contract, alice, owner, usdc_contract
):
    amount = mint_token(owner, usdc_contract, alice, 10_000)
    assert usdc_contract.balanceOf(alice) == amount

    with boa.env.prank(alice):
        usdc_contract.approve(pasanaku_contract.address, amount)
        pasanaku_contract.addCollateral(usdc_contract.address, amount)

    assert usdc_contract.balanceOf(pasanaku_contract.address) == amount

    with boa.env.prank(alice):
        pasanaku_contract.removeCollateral(usdc_contract.address, amount)
        assert pasanaku_contract.collateralReserves(usdc_contract.address) == 0

    assert pasanaku_contract.collateralReserves(usdc_contract.address) == 0
    assert pasanaku_contract.freeCollateral(alice, usdc_contract.address) == 0
    assert usdc_contract.balanceOf(alice) == amount


def test_deposit_multiple_users(pasanaku_contract, tokens, users, owner):
    for token in tokens:
        collateral_reserves = 0
        for user in users:
            amount = mint_token(owner, token, user, 10_000)
            assert token.balanceOf(user) == amount

            with boa.env.prank(user):
                token.approve(pasanaku_contract.address, amount)
                pasanaku_contract.addCollateral(token.address, amount)
                collateral_reserves += amount

        assert (
            pasanaku_contract.collateralReserves(token.address) == collateral_reserves
        )
        assert pasanaku_contract.freeCollateral(user, token.address) == amount
        assert pasanaku_contract.lockedCollateral(user, 0) == 0


def test_deposit_multiple_users_and_withdraw(pasanaku_contract, tokens, users, owner):
    for token in tokens:
        for user in users:
            amount = mint_token(owner, token, user, 10_000)
            assert token.balanceOf(user) == amount

            with boa.env.prank(user):
                token.approve(pasanaku_contract.address, amount)
                pasanaku_contract.addCollateral(token.address, amount)

    for token in tokens:
        for user in users:
            amount = mint_token(owner, token, user, 10_000)
            with boa.env.prank(user):
                pasanaku_contract.removeCollateral(token.address, amount)

    assert pasanaku_contract.collateralReserves(token.address) == 0
    assert pasanaku_contract.freeCollateral(user, token.address) == 0
    assert pasanaku_contract.lockedCollateral(user, 0) == 0


def test_add_collateral_zero_amount_reverts(pasanaku_contract, alice, usdc_contract):
    with boa.reverts("pasanaku: invalid amount"):
        with boa.env.prank(alice):
            pasanaku_contract.addCollateral(usdc_contract.address, 0)


def test_add_collateral_unsupported_asset_reverts(pasanaku_contract, alice):
    fake = boa.env.generate_address()
    with boa.reverts("pasanaku: unsupported asset"):
        with boa.env.prank(alice):
            pasanaku_contract.addCollateral(fake, 100)


def test_remove_collateral_zero_amount_reverts(pasanaku_contract, alice, usdc_contract):
    with boa.reverts("pasanaku: invalid amount"):
        with boa.env.prank(alice):
            pasanaku_contract.removeCollateral(usdc_contract.address, 0)


def test_remove_collateral_unsupported_asset_reverts(pasanaku_contract, alice):
    fake = boa.env.generate_address()
    with boa.reverts("pasanaku: unsupported asset"):
        with boa.env.prank(alice):
            pasanaku_contract.removeCollateral(fake, 100)


def test_remove_collateral_exceeds_free_reverts(
    pasanaku_contract, alice, owner, usdc_contract
):
    amount = mint_token(owner, usdc_contract, alice, 100)
    with boa.env.prank(alice):
        usdc_contract.approve(pasanaku_contract.address, amount)
        pasanaku_contract.addCollateral(usdc_contract.address, amount)

    with boa.reverts("pasanaku: insufficient free collateral"):
        with boa.env.prank(alice):
            pasanaku_contract.removeCollateral(usdc_contract.address, amount + 1)
