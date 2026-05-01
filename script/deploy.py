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
    dai = _require_env("PASANAKU_ASSET_DAI")
    ft_usdc = _require_env("PASANAKU_FTOKEN_USDC")
    ft_usdt = _require_env("PASANAKU_FTOKEN_USDT")
    ft_weth = _require_env("PASANAKU_FTOKEN_WETH")
    ft_dai = _require_env("PASANAKU_FTOKEN_DAI")

    supported_assets = [usdc, usdt, weth, dai]
    f_tokens = [ft_usdc, ft_usdt, ft_weth, ft_dai]

    print("--------- DEPLOYING PASANAKU ---------")
    print(f"  USDC: {usdc} -> fToken {ft_usdc}")
    print(f"  USDT: {usdt} -> fToken {ft_usdt}")
    print(f"  WETH: {weth} -> fToken {ft_weth}")
    print(f"  DAI:  {dai} -> fToken {ft_dai}")
    print("")

    contract: VyperContract = pasanaku.deploy(supported_assets, f_tokens)
    print(f"Deployed Pasanaku at: {contract.address}")
    print("--------- DEPLOY COMPLETE ---------")
    return contract


def moccasin_main() -> VyperContract:
    return deploy()
