import os

from moccasin.boa_tools import VyperContract
from src import Pasanaku as pasanaku


def _require_env(name: str) -> str:
    value = os.environ.get(name)
    if value is None or not value.strip():
        raise SystemExit(f"Missing required environment variable: {name}")
    return value.strip()


def _skim_asset() -> str:
    asset = os.environ.get("SKIM_ASSET")
    if asset is None or not asset.strip():
        raise SystemExit("Set SKIM_ASSET to a supported asset address")
    return asset.strip()


def skim() -> None:
    pasanaku_addr = _require_env("PASANAKU_ADDRESS")
    asset = _skim_asset()
    p: VyperContract = pasanaku.at(pasanaku_addr)

    print("--------- SKIM ---------")
    print(f"contract: {pasanaku_addr}")
    print(f"asset: {asset}")
    print("")
    p.skim(asset)
    print("Skim complete!")


def moccasin_main() -> None:
    skim()
