from src import pasanaku
from moccasin.boa_tools import VyperContract


def deploy() -> VyperContract:
    tokens = [
        "0x1234567890123456789012345678901234567890",
        "0x1234567890123456789012345678901234567890",
        "0x1234567890123456789012345678901234567890",
    ]
    
    pasanaku_contract: VyperContract = pasanaku.deploy(tokens)
    return pasanaku_contract


def moccasin_main() -> VyperContract:
    return deploy()
