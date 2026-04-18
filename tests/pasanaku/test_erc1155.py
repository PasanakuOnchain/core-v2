ERC165_ID = (0x01FFC9A7).to_bytes(4, "big")
ERC1155_ID = (0xD9B67A26).to_bytes(4, "big")


def test_supports_interface_erc165(pasanaku_contract):
    assert pasanaku_contract.supportsInterface(ERC165_ID) is True


def test_supports_interface_erc1155(pasanaku_contract):
    assert pasanaku_contract.supportsInterface(ERC1155_ID) is True


def test_balance_of_zero_before_finalize(pasanaku_contract, alice):
    assert pasanaku_contract.balanceOf(alice, 0) == 0


def test_balance_of_one_after_finalize(pasanaku_contract, started_lobby, funded_users):
    for user in funded_users:
        assert pasanaku_contract.balanceOf(user, started_lobby) == 1


def test_balance_of_batch(pasanaku_contract, started_lobby, funded_users):
    accounts = funded_users[:3]
    ids = [started_lobby] * 3
    balances = pasanaku_contract.balanceOfBatch(accounts, ids)
    for b in balances:
        assert b == 1


def test_exists_after_finalize(pasanaku_contract, started_lobby):
    assert pasanaku_contract.exists(started_lobby) is True


def test_total_supply_after_finalize(pasanaku_contract, started_lobby):
    assert pasanaku_contract.total_supply(started_lobby) == 12


def test_owner_is_deployer(pasanaku_contract, owner):
    assert pasanaku_contract.owner() == owner
