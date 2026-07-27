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
    assert shares == assets
    assert pasanaku_contract.free_shares(alice) == shares
    assert vault_contract.balanceOf(pasanaku_contract.address) == shares


def test_withdraw_burns_only_free_shares(
    pasanaku_contract,
    usdc_contract,
    owner,
    alice,
):
    assets = PASANAKU_AMOUNT_RAW
    _deposit(pasanaku_contract, usdc_contract, owner, alice, assets)
    with boa.env.prank(alice):
        burned = pasanaku_contract.withdraw(assets // 2, alice)
    assert burned == assets // 2
    assert pasanaku_contract.free_shares(alice) == assets // 2
    assert usdc_contract.balanceOf(alice) == assets // 2


def test_redeem_returns_assets(
    pasanaku_contract,
    usdc_contract,
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
    with boa.env.prank(alice):
        assets = pasanaku_contract.redeem(shares, alice)
    assert assets == PASANAKU_AMOUNT_RAW
    assert pasanaku_contract.free_shares(alice) == 0


def test_locked_shares_cannot_be_withdrawn(
    pasanaku_contract,
    usdc_contract,
    owner,
    alice,
):
    needed = pledge(PASANAKU_AMOUNT_RAW, 6)
    _deposit(pasanaku_contract, usdc_contract, owner, alice, needed)
    with boa.env.prank(alice):
        token_id = create_pasanaku(
            pasanaku_contract,
            PASANAKU_AMOUNT_RAW,
            6,
        )
    assert pasanaku_contract.free_shares(alice) == 0
    assert pasanaku_contract.locked_shares(token_id, alice) == needed
    with boa.reverts(dev="insufficient free shares"):
        with boa.env.prank(alice):
            pasanaku_contract.withdraw(1, alice)


def test_pledge_uses_configured_participant_count(pasanaku_contract):
    amount = PASANAKU_AMOUNT_RAW
    assert pasanaku_contract.pledge(amount, 6) == pledge(amount, 6)
    assert pasanaku_contract.pledge(amount, 12) == pledge(amount, 12)
