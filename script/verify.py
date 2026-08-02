import os

from moccasin.boa_tools import VyperContract
from moccasin.config import get_active_network
from src import Pasanaku as pasanaku

# Most recent Base deploy; override with PASANAKU_ADDRESS.
_DEFAULT_ADDRESS = "0x93ecCcd469BB42f8F78eD4cA24EAd578e1218835"


def verify() -> VyperContract:
    active_network = get_active_network()
    address = os.environ.get("PASANAKU_ADDRESS", _DEFAULT_ADDRESS).strip()
    if not address:
        raise SystemExit("Set PASANAKU_ADDRESS to the deployed contract address")

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

    # Bind source to an existing deployment (no broadcast).
    contract: VyperContract = pasanaku.at(address)
    if contract._ctor is not None:
        contract.ctor_calldata = contract._ctor.prepare_calldata(
            asset_address, vault_address, fee, yield_fee
        )

    print("--------- VERIFYING PASANAKU ---------")
    print(f"  Network: {active_network.name}")
    print(f"  Address: {contract.address}")
    print(f"  Asset:   {asset}")
    print(f"  Vault:   {vault}")
    print(f"  Creation fee (wei): {fee}")
    print(f"  Yield fee (bps): {yield_fee}")
    print("")

    result = active_network.moccasin_verify(contract)
    result.wait_for_verification()
    print("  Verified!")
    return contract


def moccasin_main() -> VyperContract:
    return verify()
