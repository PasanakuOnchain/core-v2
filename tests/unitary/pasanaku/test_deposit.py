import boa


def _fund_round_deposit(asset, pasanaku, owner, participant, amount):
    with boa.env.prank(owner):
        asset.mint(participant, amount)
    with boa.env.prank(participant):
        asset.approve(pasanaku.address, amount)


def test_obligor_deposit_is_recorded(
    pasanaku_contract,
    usdc_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    payer = started_pasanaku["users"][1]
    _fund_round_deposit(
        usdc_contract,
        pasanaku_contract,
        owner,
        payer,
        amount,
    )
    with boa.env.prank(payer):
        pasanaku_contract.deposit_to_pasanaku(amount, token_id)
    assert pasanaku_contract.deposited_for_pasanaku(token_id, 0, payer)
    assert pasanaku_contract.successful_obligated_deposits(
        token_id, payer
    ) == 1
    assert pasanaku_contract.pool_escrow(token_id) == amount


def test_round_recipient_cannot_deposit(
    pasanaku_contract,
    usdc_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    recipient = started_pasanaku["users"][0]
    _fund_round_deposit(
        usdc_contract,
        pasanaku_contract,
        owner,
        recipient,
        amount,
    )
    with boa.reverts(dev="active participant cannot deposit"):
        with boa.env.prank(recipient):
            pasanaku_contract.deposit_to_pasanaku(amount, token_id)


def test_duplicate_round_deposit_reverts(
    pasanaku_contract,
    usdc_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    payer = started_pasanaku["users"][1]
    _fund_round_deposit(
        usdc_contract,
        pasanaku_contract,
        owner,
        payer,
        amount * 2,
    )
    with boa.env.prank(payer):
        pasanaku_contract.deposit_to_pasanaku(amount, token_id)
        with boa.reverts(dev="account already deposited"):
            pasanaku_contract.deposit_to_pasanaku(amount, token_id)


def test_wrong_round_amount_reverts(
    pasanaku_contract,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    payer = started_pasanaku["users"][1]
    with boa.reverts(dev="invalid deposit amount"):
        with boa.env.prank(payer):
            pasanaku_contract.deposit_to_pasanaku(
                started_pasanaku["amount_raw"] - 1,
                token_id,
            )
