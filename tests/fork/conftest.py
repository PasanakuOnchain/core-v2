import os

import boa
import pytest

from src import Pasanaku as pasanaku
from tests.fork.helpers import load_erc20, load_fluid_fusdc
from tests.utils.constants import (
    MAINNET_FLUID_FUSDC,
    MAINNET_USDC,
    MAX_YIELD_FEE,
    PASANAKU_AMOUNT_RAW,
    PARTICIPANT_COUNT,
)
from tests.utils.helpers import create_and_join_all

MAINNET_CHAIN_ID = 1


def _active_moccasin_network():
    try:
        from moccasin.config import get_or_initialize_config

        return get_or_initialize_config().get_active_network()
    except Exception:
        return None


def _resolve_contract_address(network, name, fallback):
    if network is None:
        return fallback
    named = getattr(network, "named_contracts", None) or {}
    contract = named.get(name)
    address = getattr(contract, "address", None) if contract is not None else None
    return address or fallback


def _env_chain_id():
    get_chain_id = getattr(boa.env, "get_chain_id", None)
    if callable(get_chain_id):
        return int(get_chain_id())
    patch = getattr(getattr(boa.env, "evm", None), "patch", None)
    chain_id = getattr(patch, "chain_id", None)
    return int(chain_id) if chain_id is not None else None


@pytest.fixture(scope="module", autouse=True)
def mainnet_fork():
    """Ensure a mainnet fork env via Moccasin, or fall back to ETH_RPC_URL."""
    network = _active_moccasin_network()
    if network is not None and network.is_fork:
        configured_chain_id = network.chain_id
        runtime_chain_id = _env_chain_id()
        if configured_chain_id not in (None, MAINNET_CHAIN_ID):
            pytest.skip(
                "fork tests require Ethereum mainnet "
                f"(chain_id=1), got config chain_id={configured_chain_id}"
            )
        if runtime_chain_id not in (None, MAINNET_CHAIN_ID):
            pytest.skip(
                "fork tests require Ethereum mainnet "
                f"(chain_id=1), got runtime chain_id={runtime_chain_id}"
            )
        yield
        return

    rpc_url = os.environ.get("ETH_RPC_URL") or os.environ.get("FORK_URL")
    if not rpc_url:
        pytest.skip(
            "fork tests require `mox test --network ethereum` "
            "(or ETH_RPC_URL / FORK_URL for plain pytest)"
        )

    block = os.environ.get("FORK_BLOCK", "safe")
    block_identifier = int(block) if str(block).isdigit() else block
    with boa.fork(rpc_url, block_identifier=block_identifier):
        runtime_chain_id = _env_chain_id()
        if runtime_chain_id not in (None, MAINNET_CHAIN_ID):
            pytest.skip(
                "fork tests require Ethereum mainnet "
                f"(chain_id=1), got {runtime_chain_id}"
            )
        yield


@pytest.fixture(autouse=True)
def isolate_fork_case(mainnet_fork, pasanaku_contract):
    with boa.env.anchor():
        yield


@pytest.fixture(scope="module")
def usdc_contract(mainnet_fork):
    network = _active_moccasin_network()
    address = _resolve_contract_address(network, "usdc", MAINNET_USDC)
    return load_erc20(address)


@pytest.fixture(scope="module")
def vault_contract(mainnet_fork):
    network = _active_moccasin_network()
    address = _resolve_contract_address(network, "fluid_fusdc", MAINNET_FLUID_FUSDC)
    vault = load_fluid_fusdc(address)
    # Keep the fork rate non-1:1 while making both supported pledge sizes
    # convert without a deposit/withdraw rounding gap.
    vault.set_token_exchange_price(12 * 10**11)
    return vault


@pytest.fixture(scope="module")
def pasanaku_contract(
    mainnet_fork,
    owner,
    usdc_contract,
    vault_contract,
):
    assert str(vault_contract.asset()).lower() == str(usdc_contract.address).lower()
    with boa.env.prank(owner):
        return pasanaku.deploy(
            usdc_contract.address,
            vault_contract.address,
            0,
            MAX_YIELD_FEE,
        )


@pytest.fixture
def started_pasanaku(
    pasanaku_contract,
    owner,
    usdc_contract,
    users,
):
    token_id = create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        PASANAKU_AMOUNT_RAW,
        PARTICIPANT_COUNT,
    )
    return {
        "token_id": token_id,
        "amount_raw": PASANAKU_AMOUNT_RAW,
        "participant_count": PARTICIPANT_COUNT,
        "users": users,
    }
