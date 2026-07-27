# pragma version ~=0.4.3
# pragma nonreentrancy on
"""
@title ERC-4626 Test Vault
@notice Minimal vault whose exchange rate changes through donations and losses.
"""


from ethereum.ercs import IERC20


from ethereum.ercs import IERC4626
implements: IERC4626


from snekmate.auth import ownable as ow
initializes: ow


from snekmate.tokens import erc20
initializes: erc20[ownable := ow]
exports: (
    erc20.owner,
    erc20.transfer,
    erc20.approve,
    erc20.transferFrom,
    erc20.name,
    erc20.symbol,
    erc20.decimals,
    erc20.balanceOf,
    erc20.allowance,
    erc20.totalSupply,
)


_ASSET: immutable(IERC20)


# @dev Optional cap on assets withdrawable in one tick (max = unlimited).
#      Models Fluid-style temporary withdrawal limits for tests.
_withdraw_limit: uint256


@deploy
@payable
def __init__(asset_: IERC20):
    _ASSET = asset_
    self._withdraw_limit = max_value(uint256)
    ow.__init__()
    erc20.__init__("Vault Share", "vSHR", 6, "vault-share", "1")


@external
@view
def asset() -> address:
    return _ASSET.address


@external
@view
def totalAssets() -> uint256:
    return staticcall _ASSET.balanceOf(self)


@external
@view
def convertToShares(assets: uint256) -> uint256:
    return self._convert_to_shares(assets, False)


@external
@view
def convertToAssets(shares: uint256) -> uint256:
    return self._convert_to_assets(shares)


@external
@view
def maxDeposit(receiver: address) -> uint256:
    return max_value(uint256)


@external
@view
def previewDeposit(assets: uint256) -> uint256:
    return self._convert_to_shares(assets, False)


@external
def deposit(assets: uint256, receiver: address) -> uint256:
    assert assets > 0  # dev: invalid assets
    shares: uint256 = self._convert_to_shares(assets, False)
    assert shares > 0  # dev: zero shares
    success: bool = extcall _ASSET.transferFrom(
        msg.sender, self, assets, default_return_value=True
    )
    assert success  # dev: transferFrom failed
    erc20._mint(receiver, shares)
    return shares


@external
@view
def maxMint(receiver: address) -> uint256:
    return max_value(uint256)


@external
@view
def previewMint(shares: uint256) -> uint256:
    return self._convert_to_assets_up(shares)


@external
def mint(shares: uint256, receiver: address) -> uint256:
    assert shares > 0  # dev: invalid shares
    assets: uint256 = self._convert_to_assets_up(shares)
    success: bool = extcall _ASSET.transferFrom(
        msg.sender, self, assets, default_return_value=True
    )
    assert success  # dev: transferFrom failed
    erc20._mint(receiver, shares)
    return assets


@external
@view
def maxWithdraw(owner: address) -> uint256:
    return self._max_withdraw(owner)


@external
@view
def previewWithdraw(assets: uint256) -> uint256:
    return self._convert_to_shares(assets, True)


@external
def withdraw(assets: uint256, receiver: address, owner: address) -> uint256:
    assert assets > 0  # dev: invalid assets
    assert assets <= self._max_withdraw(owner)  # dev: exceed withdraw limit
    shares: uint256 = self._convert_to_shares(assets, True)
    if msg.sender != owner:
        erc20._spend_allowance(owner, msg.sender, shares)
    erc20._burn(owner, shares)
    success: bool = extcall _ASSET.transfer(
        receiver, assets, default_return_value=True
    )
    assert success  # dev: transfer failed
    return shares


@external
@view
def maxRedeem(owner: address) -> uint256:
    return self._max_redeem(owner)


@external
@view
def previewRedeem(shares: uint256) -> uint256:
    return self._convert_to_assets(shares)


@external
def redeem(shares: uint256, receiver: address, owner: address) -> uint256:
    assert shares > 0  # dev: invalid shares
    assets: uint256 = self._convert_to_assets(shares)
    # Worthless shares need no liquidity; otherwise cap asset outflow.
    assert assets <= self._max_withdraw(owner)  # dev: exceed redeem limit
    if msg.sender != owner:
        erc20._spend_allowance(owner, msg.sender, shares)
    erc20._burn(owner, shares)
    success: bool = extcall _ASSET.transfer(
        receiver, assets, default_return_value=True
    )
    assert success  # dev: transfer failed
    return assets


@external
def donate(assets: uint256):
    success: bool = extcall _ASSET.transferFrom(
        msg.sender, self, assets, default_return_value=True
    )
    assert success  # dev: transferFrom failed


@external
def set_withdraw_limit(limit: uint256):
    """
    @dev Caps assets withdrawable via withdraw/redeem (and maxWithdraw).
    @param limit Asset cap; use max_value(uint256) to clear.
    """
    ow._check_owner()
    self._withdraw_limit = limit


@external
def remove_assets(receiver: address, assets: uint256):
    ow._check_owner()
    success: bool = extcall _ASSET.transfer(
        receiver, assets, default_return_value=True
    )
    assert success  # dev: transfer failed


@internal
@view
def _max_withdraw(owner: address) -> uint256:
    balance_assets: uint256 = self._convert_to_assets(erc20.balanceOf[owner])
    return min(balance_assets, self._withdraw_limit)


@internal
@view
def _max_redeem(owner: address) -> uint256:
    balance: uint256 = erc20.balanceOf[owner]
    # Worthless share balances are fully redeemable (no asset outflow).
    if self._convert_to_assets(balance) == 0:
        return balance
    return min(
        balance,
        self._convert_to_shares(self._max_withdraw(owner), False),
    )


@internal
@view
def _convert_to_shares(assets: uint256, round_up: bool) -> uint256:
    supply: uint256 = erc20.totalSupply
    total: uint256 = staticcall _ASSET.balanceOf(self)
    if supply == 0 or total == 0:
        return assets
    numerator: uint256 = assets * supply
    if round_up and numerator % total != 0:
        return numerator // total + 1
    return numerator // total


@internal
@view
def _convert_to_assets(shares: uint256) -> uint256:
    supply: uint256 = erc20.totalSupply
    if supply == 0:
        return shares
    return shares * staticcall _ASSET.balanceOf(self) // supply


@internal
@view
def _convert_to_assets_up(shares: uint256) -> uint256:
    supply: uint256 = erc20.totalSupply
    total: uint256 = staticcall _ASSET.balanceOf(self)
    if supply == 0 or total == 0:
        return shares
    numerator: uint256 = shares * total
    if numerator % supply != 0:
        return numerator // supply + 1
    return numerator // supply
