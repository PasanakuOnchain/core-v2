import boa
from src._mocks import erc20_mock

LOBBY_AMOUNT = 100 * 10**6


def test_collect_protocol_fees_sends_balance_to_owner(
    pasanaku_contract, owner, usdc_contract, protocol_fee
):
    with boa.env.prank(owner):
        pasanaku_contract.create(
            usdc_contract.address, LOBBY_AMOUNT, value=protocol_fee
        )

    contract_eth = boa.env.get_balance(pasanaku_contract.address)
    assert contract_eth == protocol_fee

    owner_before = boa.env.get_balance(owner)
    pasanaku_contract.collectProtocolFees()

    assert boa.env.get_balance(pasanaku_contract.address) == 0
    assert boa.env.get_balance(owner) == owner_before + contract_eth


def test_skim_unsupported_asset_transfers_to_owner(pasanaku_contract, owner):
    with boa.env.prank(owner):
        token = erc20_mock.deploy("Random", "RND", 18, 0, "random", "1")
        token.mint(pasanaku_contract.address, 100 * 10**18)

    owner_before = token.balanceOf(owner)
    pasanaku_contract.skim(token.address, 50 * 10**18)

    assert token.balanceOf(owner) - owner_before == 50 * 10**18


def test_skim_supported_asset_only_excess(pasanaku_contract, owner, usdc_contract):
    extra = 500 * 10**6
    with boa.env.prank(owner):
        usdc_contract.transfer(pasanaku_contract.address, extra)

    owner_before = usdc_contract.balanceOf(owner)
    pasanaku_contract.skim(usdc_contract.address, extra)

    assert usdc_contract.balanceOf(owner) - owner_before == extra


def test_skim_supported_asset_insufficient_diff_reverts(
    pasanaku_contract, usdc_contract
):
    with boa.reverts("pasanaku: insufficient difference"):
        pasanaku_contract.skim(usdc_contract.address, 1)
