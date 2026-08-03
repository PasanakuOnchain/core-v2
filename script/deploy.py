import os

from moccasin.boa_tools import VyperContract
from moccasin.config import get_active_network
from src import Pasanaku as pasanaku  # pyright: ignore[reportAttributeAccessIssue]


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if value is None or not value.strip():
        raise SystemExit(f"Missing required environment variable: {name}")
    return value.strip()


def deploy() -> VyperContract:
    active_network = get_active_network()

    asset = active_network.get_named_contract("usdc")
    if asset is None:
        raise SystemExit("Missing required named contract")
    asset_address = asset.address

    vault = active_network.get_named_contract("fluid_fusdc")
    if vault is None:
        raise SystemExit("Missing required named contract")
    vault_address = vault.address

    fee = int(os.environ.get("PASANAKU_CREATE_FEE_WEI", "0"))
    yield_fee = int(os.environ.get("PASANAKU_YIELD_FEE_BPS", "0"))

    print("--------- DEPLOYING PASANAKU ---------")
    print(f"  Asset: {asset}")
    print(f"  Vault: {vault}")
    print(f"  Creation fee (wei): {fee}")
    print(f"  Yield fee (bps): {yield_fee}")
    print("")

    contract: VyperContract = pasanaku.deploy(
        asset_address, vault_address, fee, yield_fee
    )
    print(f"Deployed Pasanaku at: {contract.address}")
    print("")

    print("--------- DEPLOY COMPLETE ---------")
    return contract


def moccasin_main() -> VyperContract:
    return deploy()
