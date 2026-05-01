import os

from moccasin.boa_tools import VyperContract
from src import pasanaku


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if value is None or not value.strip():
        raise SystemExit(f"Missing required environment variable: {name}")
    return value.strip()


def deploy() -> VyperContract:
    usdc = _require_env("PASANAKU_ASSET_USDC")
    usdt = _require_env("PASANAKU_ASSET_USDT")
    weth = _require_env("PASANAKU_ASSET_WETH")
    supported_assets = [usdc, usdt, weth]

    print("--------- DEPLOYING PASANAKU ---------")
    print(f"  USDC: {usdc}")
    print(f"  USDT: {usdt}")
    print(f"  WETH: {weth}")
    print("")

    contract: VyperContract = pasanaku.deploy(supported_assets)
    print(f"Deployed Pasanaku at: {contract.address}")
    print("--------- DEPLOY COMPLETE ---------")
    return contract


def moccasin_main() -> VyperContract:
    return deploy()
