import os

from moccasin.boa_tools import VyperContract
from src import Pasanaku as pasanaku


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if value is None or not value.strip():
        raise SystemExit(f"Missing required environment variable: {name}")
    return value.strip()


def _recover_asset() -> str:
    asset = os.environ.get("RECOVER_ASSET")
    if asset is None or not asset.strip():
        raise SystemExit("Set RECOVER_ASSET to an unsupported ERC20 address")
    return asset.strip()


def _recover_amount() -> int:
    raw = os.environ.get("RECOVER_AMOUNT")
    if raw is None or not str(raw).strip():
        raise SystemExit("Set RECOVER_AMOUNT (raw token units)")
    return int(str(raw).strip())


def recover() -> None:
    pasanaku_addr = _require_env("PASANAKU_ADDRESS")
    asset = _recover_asset()
    amount = _recover_amount()
    p: VyperContract = pasanaku.at(pasanaku_addr)

    print("--------- RECOVER ---------")
    print(f"contract: {pasanaku_addr}")
    print(f"asset:    {asset}")
    print(f"amount:   {amount}")
    print("")
    p.recover(asset, amount)
    print("Recover complete!")


def moccasin_main() -> None:
    recover()
