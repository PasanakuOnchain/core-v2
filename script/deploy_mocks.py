from typing import List

from moccasin.boa_tools import VyperContract
from tests.mocks import erc20_mock, erc4626_mock


def deploy_mocks() -> List[VyperContract]:
    print("--------- DEPLOYING MOCK ASSET + VAULT ---------")
    asset = erc20_mock.deploy(
        "USD Coin",
        "USDC",
        6,
        10_000,
        "fake-usdc",
        "1",
    )
    vault = erc4626_mock.deploy(asset.address)
    print(f"Asset: {asset.address}")
    print(f"Vault: {vault.address}")
    return [asset, vault]


def moccasin_main() -> List[VyperContract]:
    return deploy_mocks()
