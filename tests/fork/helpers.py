import json

import boa

_TOKEN_EXCHANGE_PRICE_SLOT = 8
_TOKEN_EXCHANGE_PRICE_OFFSET = 64
_X64_MASK = (1 << 64) - 1
_EXCHANGE_PRICE_PRECISION = 10**12
_MIN_TOKEN_EXCHANGE_PRICE = 10**6

_ERC20_ABI = [
    {
        "type": "function",
        "name": "approve",
        "stateMutability": "nonpayable",
        "inputs": [
            {"name": "spender", "type": "address"},
            {"name": "amount", "type": "uint256"},
        ],
        "outputs": [{"name": "", "type": "bool"}],
    },
    {
        "type": "function",
        "name": "balanceOf",
        "stateMutability": "view",
        "inputs": [{"name": "account", "type": "address"}],
        "outputs": [{"name": "", "type": "uint256"}],
    },
    {
        "type": "function",
        "name": "totalSupply",
        "stateMutability": "view",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256"}],
    },
]

_ERC4626_ABI = _ERC20_ABI + [
    {
        "type": "function",
        "name": "asset",
        "stateMutability": "view",
        "inputs": [],
        "outputs": [{"name": "", "type": "address"}],
    },
    {
        "type": "function",
        "name": "totalAssets",
        "stateMutability": "view",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256"}],
    },
    {
        "type": "function",
        "name": "previewDeposit",
        "stateMutability": "view",
        "inputs": [{"name": "assets", "type": "uint256"}],
        "outputs": [{"name": "", "type": "uint256"}],
    },
    {
        "type": "function",
        "name": "previewWithdraw",
        "stateMutability": "view",
        "inputs": [{"name": "assets", "type": "uint256"}],
        "outputs": [{"name": "", "type": "uint256"}],
    },
    {
        "type": "function",
        "name": "previewRedeem",
        "stateMutability": "view",
        "inputs": [{"name": "shares", "type": "uint256"}],
        "outputs": [{"name": "", "type": "uint256"}],
    },
    {
        "type": "function",
        "name": "maxWithdraw",
        "stateMutability": "view",
        "inputs": [{"name": "owner", "type": "address"}],
        "outputs": [{"name": "", "type": "uint256"}],
    },
]


def load_erc20(address):
    factory = boa.loads_abi(json.dumps(_ERC20_ABI), name="ForkERC20")
    return ForkERC20(factory.at(address))


def load_fluid_fusdc(address):
    factory = boa.loads_abi(json.dumps(_ERC4626_ABI), name="FluidFUSDC")
    return FluidFUSDC(factory.at(address))


class ForkERC20:
    """Real fork token with a mock-compatible test funding method."""

    collateral_buffer = 2

    def __init__(self, contract):
        self._contract = contract

    @property
    def address(self):
        return self._contract.address

    def mint(self, receiver, amount):
        current_balance = self._contract.balanceOf(receiver)
        boa.deal(self._contract, receiver, current_balance + amount)

    def __getattr__(self, name):
        return getattr(self._contract, name)


class FluidFUSDC:
    """fUSDC facade with deterministic exchange-price controls for fork tests."""

    def __init__(self, contract):
        self._contract = contract

    @property
    def address(self):
        return self._contract.address

    def donate(self, assets):
        self._set_total_assets(self.totalAssets() + assets)

    def remove_assets(self, _receiver, assets):
        self._set_total_assets(max(0, self.totalAssets() - assets))

    def set_token_exchange_price(self, token_exchange_price):
        if not 0 < token_exchange_price <= _X64_MASK:
            raise ValueError("fUSDC token exchange price is outside uint64")
        self._write_token_exchange_price(token_exchange_price)

    def _set_total_assets(self, target_assets):
        total_supply = self.totalSupply()
        if total_supply == 0:
            raise AssertionError("cannot change fUSDC price with zero total supply")

        token_exchange_price = (
            target_assets * _EXCHANGE_PRICE_PRECISION + total_supply - 1
        ) // total_supply
        token_exchange_price = min(
            max(token_exchange_price, _MIN_TOKEN_EXCHANGE_PRICE),
            _X64_MASK,
        )

        for _ in range(3):
            self._write_token_exchange_price(token_exchange_price)
            actual_assets = self.totalAssets()
            if actual_assets == target_assets or actual_assets == 0:
                break
            token_exchange_price = (
                token_exchange_price * target_assets + actual_assets - 1
            ) // actual_assets
            token_exchange_price = min(
                max(token_exchange_price, _MIN_TOKEN_EXCHANGE_PRICE),
                _X64_MASK,
            )

    def _write_token_exchange_price(self, token_exchange_price):
        packed = boa.env.get_storage(
            self.address,
            _TOKEN_EXCHANGE_PRICE_SLOT,
        )
        token_price_mask = _X64_MASK << _TOKEN_EXCHANGE_PRICE_OFFSET
        updated = (packed & ~token_price_mask) | (
            token_exchange_price << _TOKEN_EXCHANGE_PRICE_OFFSET
        )
        boa.env.set_storage(
            self.address,
            _TOKEN_EXCHANGE_PRICE_SLOT,
            updated,
        )

    def __getattr__(self, name):
        return getattr(self._contract, name)
