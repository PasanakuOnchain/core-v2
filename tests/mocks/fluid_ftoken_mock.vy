# pragma version ~=0.4.3
# pragma nonreentrancy off
"""
@title ERC4626-style Fluid fToken mock
@notice Minimal deposit/withdraw/redeem for tests; shares are ERC20-like via this contract.
"""
from ethereum.ercs import IERC20


underlying: public(immutable(address))
total_supply: uint256
balance_of: HashMap[address, uint256]


@deploy
@payable
def __init__(asset_: address):
    underlying = asset_


@external
@view
def asset() -> address:
    return underlying


@internal
@view
def _total_assets() -> uint256:
    return staticcall IERC20(underlying).balanceOf(self)


@external
@view
def totalAssets() -> uint256:
    return self._total_assets()


@external
@view
def balanceOf(account: address) -> uint256:
    return self.balance_of[account]


@external
@view
def totalSupply() -> uint256:
    return self.total_supply


@external
def deposit(assets: uint256, receiver: address) -> uint256:
    assert assets > 0
    extcall IERC20(underlying).transferFrom(msg.sender, self, assets)
    ta: uint256 = self._total_assets()
    ts: uint256 = self.total_supply
    shares: uint256 = 0
    if ts == 0:
        shares = assets
    else:
        shares = assets * ts // (ta - assets)
    assert shares > 0
    self.total_supply = ts + shares
    self.balance_of[receiver] += shares
    return shares


@external
def withdraw(assets: uint256, receiver: address, owner_: address) -> uint256:
    assert assets > 0
    assert msg.sender == owner_  # dev: not owner
    ta: uint256 = self._total_assets()
    ts: uint256 = self.total_supply
    assert ta > 0 and ts > 0
    shares: uint256 = (assets * ts + ta - 1) // ta
    assert self.balance_of[owner_] >= shares  # dev: burn exceeds balance # nosplit
    assets_out: uint256 = shares * ta // ts
    self.balance_of[owner_] -= shares
    self.total_supply = ts - shares
    extcall IERC20(underlying).transfer(receiver, assets_out)
    return shares


@external
def redeem(shares: uint256, receiver: address, owner_: address) -> uint256:
    assert shares > 0
    assert msg.sender == owner_
    ta: uint256 = self._total_assets()
    ts: uint256 = self.total_supply
    assert ts > 0
    assets_out: uint256 = shares * ta // ts
    self.balance_of[owner_] -= shares
    self.total_supply = ts - shares
    extcall IERC20(underlying).transfer(receiver, assets_out)
    return assets_out


@external
def inject_yield_from(donor: address, amount: uint256):
    """@notice Donate underlying into the pool without minting shares (raises exchange rate)."""
    assert amount > 0
    extcall IERC20(underlying).transferFrom(donor, self, amount)
