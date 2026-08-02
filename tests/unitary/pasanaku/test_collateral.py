import boa

from tests.utils.constants import PASANAKU_AMOUNT_RAW
from tests.utils.helpers import create_pasanaku, pledge


def _deposit(pasanaku, asset, owner, user, assets):
    with boa.env.prank(owner):
        asset.mint(user, assets)
    with boa.env.prank(user):
        asset.approve(pasanaku.address, assets)
        return pasanaku.deposit(assets, user)


def test_deposit_credits_vault_shares(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    alice,
):
    assets = PASANAKU_AMOUNT_RAW
    shares = _deposit(
        pasanaku_contract,
        usdc_contract,
        owner,
        alice,
        assets,
    )
    assert shares > 0
    assert pasanaku_contract.free_shares(alice) == shares
    assert vault_contract.balanceOf(pasanaku_contract.address) == shares


def test_withdraw_burns_only_free_shares(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    alice,
):
    assets = PASANAKU_AMOUNT_RAW
    deposited_shares = _deposit(
        pasanaku_contract,
        usdc_contract,
        owner,
        alice,
        assets,
    )
    expected_burned = vault_contract.previewWithdraw(assets // 2)
    with boa.env.prank(alice):
        burned = pasanaku_contract.withdraw(assets // 2, alice)
    assert burned == expected_burned
    assert pasanaku_contract.free_shares(alice) == deposited_shares - burned
    assert usdc_contract.balanceOf(alice) == assets // 2


def test_redeem_returns_assets(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    alice,
):
    shares = _deposit(
        pasanaku_contract,
        usdc_contract,
        owner,
        alice,
        PASANAKU_AMOUNT_RAW,
    )
    expected_assets = vault_contract.previewRedeem(shares)
    with boa.env.prank(alice):
        assets = pasanaku_contract.redeem(shares, alice)
    assert assets == expected_assets
    assert pasanaku_contract.free_shares(alice) == 0


def test_locked_shares_cannot_be_withdrawn(
    pasanaku_contract,
    usdc_contract,
    vault_contract,
    owner,
    alice,
):
    pledge_assets = pledge(PASANAKU_AMOUNT_RAW, 6)
    needed = vault_contract.previewWithdraw(pledge_assets)
    deposited = _deposit(
        pasanaku_contract,
        usdc_contract,
        owner,
        alice,
        pledge_assets + getattr(usdc_contract, "collateral_buffer", 0),
    )
    with boa.env.prank(alice):
        token_id = create_pasanaku(
            pasanaku_contract,
            PASANAKU_AMOUNT_RAW,
            6,
        )
    assert pasanaku_contract.free_shares(alice) == deposited - needed
    assert pasanaku_contract.locked_shares(token_id, alice) == needed
    free_assets = vault_contract.previewRedeem(pasanaku_contract.free_shares(alice))
    with boa.reverts(dev="insufficient free shares"):
        with boa.env.prank(alice):
            pasanaku_contract.withdraw(free_assets + 1, alice)


def test_pledge_uses_configured_participant_count(pasanaku_contract):
    amount = PASANAKU_AMOUNT_RAW
    assert pasanaku_contract.pledge(amount, 6) == pledge(amount, 6)
    assert pasanaku_contract.pledge(amount, 12) == pledge(amount, 12)
