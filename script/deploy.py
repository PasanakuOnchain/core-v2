import os

from moccasin.boa_tools import VyperContract
from src import Pasanaku as pasanaku


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if value is None or not value.strip():
        raise SystemExit(f"Missing required environment variable: {name}")
    return value.strip()


def deploy() -> VyperContract:
    asset = _require_env("PASANAKU_ASSET")
    vault = _require_env("PASANAKU_VAULT")
    fee = int(os.environ.get("PASANAKU_CREATE_FEE_WEI", "0"))
    yield_fee = int(os.environ.get("PASANAKU_YIELD_FEE_BPS", "0"))

    print("--------- DEPLOYING PASANAKU ---------")
    print(f"  Asset: {asset}")
    print(f"  Vault: {vault}")
    print(f"  Creation fee (wei): {fee}")
    print(f"  Yield fee (bps): {yield_fee}")
    print("")

    contract: VyperContract = pasanaku.deploy(asset, vault, fee, yield_fee)
    print(f"Deployed Pasanaku at: {contract.address}")
    print("--------- DEPLOY COMPLETE ---------")
    return contract


def moccasin_main() -> VyperContract:
    return deploy()
