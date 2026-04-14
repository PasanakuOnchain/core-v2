import boa

LOBBY_AMOUNT = 100 * 10**6
PARTICIPANTS_COUNT = 12


def _get_round_info(pasanaku_contract, token_id):
    rs = pasanaku_contract.rotatingSavings(token_id)
    participants = list(rs[0])
    current_index = rs[3]
    current = participants[current_index]
    depositors = [p for p in participants if p != current]
    return current, depositors


def _do_deposits(owner, usdc_contract, pasanaku_contract, token_id, depositors, amount):
    for depositor in depositors:
        with boa.env.prank(owner):
            usdc_contract.mint(depositor, amount)
        with boa.env.prank(depositor):
            usdc_contract.approve(pasanaku_contract.address, amount)
            pasanaku_contract.deposit(token_id)


# --- Happy path ---


def test_deposit_succeeds(
    pasanaku_contract, started_lobby, owner, usdc_contract, lobby_amount
):
    current, depositors = _get_round_info(pasanaku_contract, started_lobby)
    depositor = depositors[0]

    with boa.env.prank(owner):
        usdc_contract.mint(depositor, lobby_amount)
    with boa.env.prank(depositor):
        usdc_contract.approve(pasanaku_contract.address, lobby_amount)
        result = pasanaku_contract.deposit(started_lobby)

    assert result is True
    rs = pasanaku_contract.rotatingSavings(started_lobby)
    assert rs[4] == lobby_amount


def test_claim_succeeds(
    pasanaku_contract, started_lobby, owner, usdc_contract, lobby_amount, protocol_fee
):
    current, depositors = _get_round_info(pasanaku_contract, started_lobby)
    _do_deposits(
        owner, usdc_contract, pasanaku_contract, started_lobby, depositors, lobby_amount
    )

    balance_before = usdc_contract.balanceOf(current)
    with boa.env.prank(current):
        result = pasanaku_contract.claim(started_lobby, value=protocol_fee)

    assert result is True
    balance_after = usdc_contract.balanceOf(current)
    assert balance_after - balance_before == lobby_amount * (PARTICIPANTS_COUNT - 1)

    rs = pasanaku_contract.rotatingSavings(started_lobby)
    assert rs[3] == 1
    assert rs[4] == 0


def test_skip_succeeds(
    pasanaku_contract, started_lobby, owner, usdc_contract, lobby_amount, protocol_fee
):
    current, depositors = _get_round_info(pasanaku_contract, started_lobby)
    _do_deposits(
        owner, usdc_contract, pasanaku_contract, started_lobby, depositors, lobby_amount
    )

    balance_before = usdc_contract.balanceOf(current)
    caller = boa.env.generate_address()
    boa.env.set_balance(caller, 10**18)
    with boa.env.prank(caller):
        result = pasanaku_contract.skip(started_lobby, value=protocol_fee)

    assert result is True
    balance_after = usdc_contract.balanceOf(current)
    assert balance_after - balance_before == lobby_amount * (PARTICIPANTS_COUNT - 1)

    rs = pasanaku_contract.rotatingSavings(started_lobby)
    assert rs[3] == 1
    assert rs[4] == 0


# --- Reverts ---


def test_deposit_non_participant_reverts(pasanaku_contract, started_lobby):
    outsider = boa.env.generate_address()
    with boa.reverts("pasanaku: cannot deposit"):
        with boa.env.prank(outsider):
            pasanaku_contract.deposit(started_lobby)


def test_deposit_current_index_cannot_deposit(
    pasanaku_contract, started_lobby, owner, usdc_contract, lobby_amount
):
    current, _ = _get_round_info(pasanaku_contract, started_lobby)
    with boa.env.prank(owner):
        usdc_contract.mint(current, lobby_amount)
    with boa.env.prank(current):
        usdc_contract.approve(pasanaku_contract.address, lobby_amount)

    with boa.reverts("pasanaku: cannot deposit"):
        with boa.env.prank(current):
            pasanaku_contract.deposit(started_lobby)


def test_deposit_already_deposited_reverts(
    pasanaku_contract, started_lobby, owner, usdc_contract, lobby_amount
):
    _, depositors = _get_round_info(pasanaku_contract, started_lobby)
    depositor = depositors[0]

    with boa.env.prank(owner):
        usdc_contract.mint(depositor, lobby_amount * 2)
    with boa.env.prank(depositor):
        usdc_contract.approve(pasanaku_contract.address, lobby_amount * 2)
        pasanaku_contract.deposit(started_lobby)

    with boa.reverts("pasanaku: cannot deposit"):
        with boa.env.prank(depositor):
            pasanaku_contract.deposit(started_lobby)


def test_claim_insufficient_fee_reverts(pasanaku_contract, started_lobby):
    current, _ = _get_round_info(pasanaku_contract, started_lobby)
    with boa.reverts("pasanaku: insufficient fee"):
        with boa.env.prank(current):
            pasanaku_contract.claim(started_lobby, value=0)


def test_claim_wrong_participant_reverts(
    pasanaku_contract, started_lobby, protocol_fee
):
    current, depositors = _get_round_info(pasanaku_contract, started_lobby)
    wrong = depositors[0]
    with boa.reverts("pasanaku: cannot claim"):
        with boa.env.prank(wrong):
            pasanaku_contract.claim(started_lobby, value=protocol_fee)
