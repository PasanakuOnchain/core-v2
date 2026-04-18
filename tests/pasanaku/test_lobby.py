import boa

LOBBY_AMOUNT = 100 * 10**6
PARTICIPANTS_COUNT = 12


def test_create_lobby_returns_token_id(
    pasanaku_contract, owner, usdc_contract, protocol_fee
):
    with boa.env.prank(owner):
        first = pasanaku_contract.create(
            usdc_contract.address, LOBBY_AMOUNT, value=protocol_fee
        )
        second = pasanaku_contract.create(
            usdc_contract.address, LOBBY_AMOUNT, value=protocol_fee
        )

    assert first == 0
    assert second == 1


def test_create_lobby_sets_state(pasanaku_contract, owner, usdc_contract, protocol_fee):
    with boa.env.prank(owner):
        token_id = pasanaku_contract.create(
            usdc_contract.address, LOBBY_AMOUNT, value=protocol_fee
        )

    rs = pasanaku_contract.rotatingSavings(token_id)
    assert rs[1] == usdc_contract.address
    assert rs[2] == LOBBY_AMOUNT
    assert rs[3] == 0
    assert rs[4] == 0
    assert rs[5] == token_id
    assert rs[6] is False
    assert rs[7] is False


def test_join_lobby_adds_participant(
    pasanaku_contract, funded_users, lobby_id, protocol_fee, usdc_contract
):
    user = funded_users[0]
    with boa.env.prank(user):
        pasanaku_contract.join(lobby_id, value=protocol_fee)

    rs = pasanaku_contract.rotatingSavings(lobby_id)
    assert len(rs[0]) == 1
    assert rs[0][0] == user

    expected_locked = LOBBY_AMOUNT * (PARTICIPANTS_COUNT - 1)
    assert pasanaku_contract.lockedCollateral(user, lobby_id) == expected_locked
    assert pasanaku_contract.freeCollateral(user, usdc_contract.address) == 0


def test_finalize_lobby_starts_game(pasanaku_contract, full_lobby, funded_users):
    with boa.env.prank(funded_users[0]):
        pasanaku_contract.finalizeLobby(full_lobby)

    rs = pasanaku_contract.rotatingSavings(full_lobby)
    assert rs[7] is True

    for user in funded_users:
        assert pasanaku_contract.balanceOf(user, full_lobby) == 1


def test_create_lobby_insufficient_fee_reverts(pasanaku_contract, owner, usdc_contract):
    with boa.reverts("pasanaku: insufficient fee"):
        with boa.env.prank(owner):
            pasanaku_contract.create(usdc_contract.address, LOBBY_AMOUNT, value=0)


def test_create_lobby_zero_amount_reverts(
    pasanaku_contract, owner, usdc_contract, protocol_fee
):
    with boa.reverts("pasanaku: invalid amount"):
        with boa.env.prank(owner):
            pasanaku_contract.create(usdc_contract.address, 0, value=protocol_fee)


def test_create_lobby_unsupported_asset_reverts(pasanaku_contract, owner, protocol_fee):
    fake = boa.env.generate_address()
    with boa.reverts("pasanaku: unsupported asset"):
        with boa.env.prank(owner):
            pasanaku_contract.create(fake, LOBBY_AMOUNT, value=protocol_fee)


def test_join_lobby_insufficient_fee_reverts(pasanaku_contract, funded_users, lobby_id):
    with boa.reverts("pasanaku: insufficient fee"):
        with boa.env.prank(funded_users[0]):
            pasanaku_contract.join(lobby_id, value=0)


def test_join_lobby_already_started_reverts(
    pasanaku_contract, started_lobby, protocol_fee
):
    outsider = boa.env.generate_address()
    boa.env.set_balance(outsider, 10**18)
    with boa.reverts("pasanaku: lobby already starded"):
        with boa.env.prank(outsider):
            pasanaku_contract.join(started_lobby, value=protocol_fee)


def test_join_lobby_already_joined_reverts(
    pasanaku_contract, funded_users, lobby_id, protocol_fee
):
    user = funded_users[0]
    with boa.env.prank(user):
        pasanaku_contract.join(lobby_id, value=protocol_fee)

    with boa.reverts("pasanaku: caller already joined"):
        with boa.env.prank(user):
            pasanaku_contract.join(lobby_id, value=protocol_fee)


def test_join_lobby_insufficient_collateral_reverts(
    pasanaku_contract, lobby_id, protocol_fee
):
    broke = boa.env.generate_address()
    boa.env.set_balance(broke, 10**18)
    with boa.reverts("pasanaku: insufficient collateral"):
        with boa.env.prank(broke):
            pasanaku_contract.join(lobby_id, value=protocol_fee)


def test_finalize_lobby_insufficient_participants_reverts(
    pasanaku_contract, funded_users, lobby_id, protocol_fee
):
    with boa.env.prank(funded_users[0]):
        pasanaku_contract.join(lobby_id, value=protocol_fee)

    with boa.reverts("pasanaku: insufficient participants"):
        with boa.env.prank(funded_users[0]):
            pasanaku_contract.finalizeLobby(lobby_id)


def test_finalize_lobby_non_participant_reverts(pasanaku_contract, full_lobby):
    outsider = boa.env.generate_address()
    boa.env.set_balance(outsider, 10**18)
    with boa.reverts("pasanaku: caller not a participant"):
        with boa.env.prank(outsider):
            pasanaku_contract.finalizeLobby(full_lobby)


def test_finalize_lobby_already_started_reverts(
    pasanaku_contract, started_lobby, funded_users
):
    with boa.reverts("pasanaku: already started"):
        with boa.env.prank(funded_users[0]):
            pasanaku_contract.finalizeLobby(started_lobby)
