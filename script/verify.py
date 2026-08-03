import os

from moccasin.boa_tools import VyperContract
from moccasin.config import get_active_network
from src import Pasanaku as pasanaku  # pyright: ignore[reportAttributeAccessIssue]

# Most recent Base deploy; override with PASANAKU_ADDRESS.
_DEFAULT_ADDRESS = "0xD559fedc59a6CeF510d55145ec965b423bdb5d4D"


def verify() -> VyperContract:
    active_network = get_active_network()
    address = os.environ.get("PASANAKU_ADDRESS", _DEFAULT_ADDRESS).strip()
    if not address:
        raise SystemExit("Set PASANAKU_ADDRESS to the deployed contract address")

    # Bind source to an existing deployment (no broadcast).
    contract: VyperContract = pasanaku.at(address)

    print("--------- VERIFYING PASANAKU ---------")
    print(f"  Network: {active_network.name}")
    print(f"  Address: {contract.address}")
    print("")

    result = active_network.moccasin_verify(contract)
    result.wait_for_verification()
    print("  Verified!")
    return contract


def moccasin_main() -> VyperContract:
    return verify()
