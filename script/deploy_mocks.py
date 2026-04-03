from typing import List
from src._mocks import erc20_mock
from moccasin.boa_tools import VyperContract

mock_tokens = [
    {
        "name": "USD Coin",
        "symbol": "USDC",
        "decimals": 6,
        "initial_supply": int(10_000 * 10**6),
        "name_eip712": "fake-usdc",
        "version_eip712": "1",
    },
    {
        "name": "Tether",
        "symbol": "USDT",
        "decimals": 6,
        "initial_supply": int(10_000 * 10**6),
        "name_eip712": "fake-usdt",
        "version_eip712": "1",
    },
    {
        "name": "Wrapped Ether",
        "symbol": "WETH",
        "decimals": 18,
        "initial_supply": int(10_000 * 10**18),
        "name_eip712": "fake-weth",
        "version_eip712": "1",
    },
]


def deploy_mocks() -> List[VyperContract]:
    contracts = []
    print("--------- DEPLOYING MOCKS ---------")
    print(f"Deploying {len(mock_tokens)} mock tokens")
    print("")
    for token in mock_tokens:
        print(f"Deploying {token['name']} ({token['symbol']})")
        contract = erc20_mock.deploy(
            token["name"],
            token["symbol"],
            token["decimals"],
            token["initial_supply"],
            token["name_eip712"],
            token["version_eip712"],
        )
        print(f"Address: {contract.address} \n")
        contracts.append(contract)
    return contracts


def moccasin_main() -> List[VyperContract]:
    return deploy_mocks()
