import boa

LOBBY_AMOUNT = 100 * 10**6
PARTICIPANTS_COUNT = 12


def test_uri_active_state(pasanaku_contract, owner, usdc_contract, protocol_fee):
    with boa.env.prank(owner):
        token_id = pasanaku_contract.create(
            usdc_contract.address, LOBBY_AMOUNT, value=protocol_fee
        )
    assert pasanaku_contract.uri(token_id) == "https://pasanaku.fun/pasanaku/active"


def test_uri_started_state(pasanaku_contract, started_lobby):
    assert (
        pasanaku_contract.uri(started_lobby) == "https://pasanaku.fun/pasanaku/started"
    )


def test_supported_assets_returns_three(
    pasanaku_contract, usdc_contract, usdt_contract, weth_contract
):
    assets = pasanaku_contract.supportedAssets()
    assert assets[0] == usdc_contract.address
    assert assets[1] == usdt_contract.address
    assert assets[2] == weth_contract.address


def test_rotating_savings_struct(pasanaku_contract, lobby_id, usdc_contract):
    rs = pasanaku_contract.rotatingSavings(lobby_id)
    assert len(rs[0]) == 0
    assert rs[1] == usdc_contract.address
    assert rs[2] == LOBBY_AMOUNT
    assert rs[3] == 0
    assert rs[4] == 0
    assert rs[5] == lobby_id
    assert rs[6] is False
    assert rs[7] is False


def test_can_deposit_logic(pasanaku_contract, started_lobby):
    rs = pasanaku_contract.rotatingSavings(started_lobby)
    participants = list(rs[0])
    current = participants[rs[3]]
    non_current = [p for p in participants if p != current][0]

    assert pasanaku_contract.canDeposit(non_current, started_lobby) is True
    assert pasanaku_contract.canDeposit(current, started_lobby) is False


def test_can_claim_logic(pasanaku_contract, started_lobby):
    rs = pasanaku_contract.rotatingSavings(started_lobby)
    participants = list(rs[0])
    current = participants[rs[3]]
    non_current = [p for p in participants if p != current][0]

    assert pasanaku_contract.canClaim(current, started_lobby) is True
    assert pasanaku_contract.canClaim(non_current, started_lobby) is False


def test_can_skip_mirrors_can_claim(pasanaku_contract, started_lobby):
    rs = pasanaku_contract.rotatingSavings(started_lobby)
    participants = list(rs[0])
    for p in participants:
        assert pasanaku_contract.canSkip(
            p, started_lobby
        ) == pasanaku_contract.canClaim(p, started_lobby)


def test_amount_to_pay(pasanaku_contract, full_lobby, lobby_amount):
    expected = lobby_amount * (PARTICIPANTS_COUNT - 1)
    assert pasanaku_contract.amountToPay(full_lobby) == expected


def test_protocol_fee_constant(pasanaku_contract, protocol_fee):
    assert pasanaku_contract.protocolFee() == protocol_fee
