import boa

from tests.utils.constants import PASANAKU_AMOUNT_RAW
from tests.utils.helpers import create_pasanaku, fund_collateral_for_users, pledge


def test_add_collateral(pasanaku_contract, owner, usdc_contract, users):
    collateral_amount = PASANAKU_AMOUNT_RAW
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, users, collateral_amount, raw=True
    )
    for user in users:
        onchain_collateral = pasanaku_contract.collateral(user, usdc_contract.address)
        assert onchain_collateral == collateral_amount


def test_add_collateral_emits_event(pasanaku_contract, owner, usdc_contract, users):
    amount = PASANAKU_AMOUNT_RAW
    participant = users[0]
    with boa.env.prank(owner):
        usdc_contract.mint(participant, amount)
    with boa.env.prank(participant):
        usdc_contract.approve(pasanaku_contract.address, amount)
        pasanaku_contract.add_collateral(usdc_contract.address, amount)

    added = [
        log
        for log in pasanaku_contract.get_logs()
        if type(log).__name__ == "CollateralAdded"
    ]
    assert len(added) == 1
    assert added[0].account == participant
    assert added[0].asset == usdc_contract.address
    assert added[0].amount == amount


def test_add_collateral_unsupported_asset_reverts(pasanaku_contract, users):
    fake_asset = boa.env.generate_address()
    with boa.reverts(dev="unsupported asset"):
        with boa.env.prank(users[0]):
            pasanaku_contract.add_collateral(fake_asset, PASANAKU_AMOUNT_RAW)


def test_add_collateral_zero_amount_reverts(pasanaku_contract, users, usdc_contract):
    with boa.reverts(dev="invalid amount"):
        with boa.env.prank(users[0]):
            pasanaku_contract.add_collateral(usdc_contract.address, 0)


def test_pledge_view_matches_helper(pasanaku_contract):
    amount_raw = PASANAKU_AMOUNT_RAW
    assert pasanaku_contract.pledge(amount_raw) == pledge(amount_raw)


def test_withdraw_collateral_blocked_when_all_locked(
    pasanaku_contract, owner, usdc_contract, users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [users[0]], amount_raw
    )
    with boa.env.prank(users[0]):
        create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)
    with boa.reverts(dev="collateral in use"):
        with boa.env.prank(users[0]):
            pasanaku_contract.withdraw_collateral(usdc_contract.address, 1)


def test_withdraw_collateral_happy_path_partial(
    pasanaku_contract, owner, usdc_contract, users
):
    """Partial withdraw of free collateral while pledge remains locked."""
    amount_raw = PASANAKU_AMOUNT_RAW
    locked = pledge(amount_raw)
    extra = PASANAKU_AMOUNT_RAW
    total = locked + extra
    participant = users[0]

    with boa.env.prank(owner):
        usdc_contract.mint(participant, total)
    with boa.env.prank(participant):
        usdc_contract.approve(pasanaku_contract.address, total)
        pasanaku_contract.add_collateral(usdc_contract.address, total)
        create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)

    assert (
        pasanaku_contract.collateral_in_use(participant, usdc_contract.address)
        == locked
    )
    assert (
        pasanaku_contract.free_collateral(participant, usdc_contract.address) == extra
    )

    pre_balance = usdc_contract.balanceOf(participant)
    with boa.env.prank(participant):
        pasanaku_contract.withdraw_collateral(usdc_contract.address, extra)

    assert usdc_contract.balanceOf(participant) == pre_balance + extra
    assert pasanaku_contract.collateral(participant, usdc_contract.address) == locked
    assert pasanaku_contract.free_collateral(participant, usdc_contract.address) == 0


def test_withdraw_collateral_insufficient_free_reverts(
    pasanaku_contract, owner, usdc_contract, users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    locked = pledge(amount_raw)
    extra = 1
    participant = users[0]
    total = locked + extra

    with boa.env.prank(owner):
        usdc_contract.mint(participant, total)
    with boa.env.prank(participant):
        usdc_contract.approve(pasanaku_contract.address, total)
        pasanaku_contract.add_collateral(usdc_contract.address, total)
        create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)

    with boa.reverts(dev="insufficient free collateral # nosplit"):
        with boa.env.prank(participant):
            pasanaku_contract.withdraw_collateral(usdc_contract.address, extra + 1)


def test_withdraw_collateral_unsupported_asset_reverts(pasanaku_contract, users):
    fake_asset = boa.env.generate_address()
    with boa.reverts(dev="unsupported asset"):
        with boa.env.prank(users[0]):
            pasanaku_contract.withdraw_collateral(fake_asset, 1)


def test_withdraw_collateral_emits_event(
    pasanaku_contract, owner, usdc_contract, users
):
    amount = PASANAKU_AMOUNT_RAW
    participant = users[0]
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [participant], amount, raw=True
    )
    with boa.env.prank(participant):
        pasanaku_contract.withdraw_collateral(usdc_contract.address, amount)

    withdrawn = [
        log
        for log in pasanaku_contract.get_logs()
        if type(log).__name__ == "CollateralWithdrawn"
    ]
    assert len(withdrawn) == 1
    assert withdrawn[0].account == participant
    assert withdrawn[0].asset == usdc_contract.address
    assert withdrawn[0].amount == amount
    assert withdrawn[0].balance_after == 0


def test_free_collateral_zero_when_all_locked(
    pasanaku_contract, owner, usdc_contract, users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [users[0]], amount_raw
    )
    with boa.env.prank(users[0]):
        create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)

    participant = users[0]
    assert pasanaku_contract.collateral(participant, usdc_contract.address) == pledge(
        amount_raw
    )
    assert pasanaku_contract.free_collateral(participant, usdc_contract.address) == 0


def test_collateral_in_use_after_join(pasanaku_contract, owner, usdc_contract, users):
    amount_raw = PASANAKU_AMOUNT_RAW
    need = pledge(amount_raw)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, users[:2], amount_raw
    )
    with boa.env.prank(users[0]):
        create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)
    assert pasanaku_contract.collateral_in_use(users[0], usdc_contract.address) == need
    with boa.env.prank(users[1]):
        pasanaku_contract.join_pasanaku(0)
    assert pasanaku_contract.collateral_in_use(users[1], usdc_contract.address) == need
