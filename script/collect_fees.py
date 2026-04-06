from src import pasanaku
from moccasin.boa_tools import VyperContract

PASANAKU_ADDRESS = "0x1234567890123456789012345678901234567890"


def collect_fees() -> None:
    p: VyperContract = pasanaku.at(PASANAKU_ADDRESS)
    print("--------- COLLECTING FEES ---------")
    print(f"Collecting fees from {PASANAKU_ADDRESS}")
    print("")
    p.collectProtocolFees()
    print("--------- FEES COLLECTED ---------")
    print(f"Fees collected: {p.balance()} ETH")
    print("")


def moccasin_main():
    collect_fees()
