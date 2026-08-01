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
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    payer = next(user for user in started_pasanaku["users"] if user != recipient)
    _fund_round_deposit(
        usdc_contract,
        pasanaku_contract,
        owner,
        payer,
        amount,
    )
    with boa.env.prank(payer):
        pasanaku_contract.deposit_to_pasanaku(amount, token_id, payer)
    assert pasanaku_contract.deposited_for_pasanaku(token_id, 0, payer)
    assert pasanaku_contract.successful_obligated_deposits(token_id, payer) == 1
    assert pasanaku_contract.pool_escrow(token_id) == amount


def test_third_party_can_deposit_on_behalf(
    pasanaku_contract,
    usdc_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    obligor = next(user for user in started_pasanaku["users"] if user != recipient)
    friend = boa.env.generate_address("friend")
    _fund_round_deposit(
        usdc_contract,
        pasanaku_contract,
        owner,
        friend,
        amount,
    )
    with boa.env.prank(friend):
        pasanaku_contract.deposit_to_pasanaku(amount, token_id, obligor)

    assert pasanaku_contract.deposited_for_pasanaku(token_id, 0, obligor)
    assert not pasanaku_contract.deposited_for_pasanaku(token_id, 0, friend)
    assert pasanaku_contract.successful_obligated_deposits(token_id, obligor) == 1
    assert pasanaku_contract.successful_obligated_deposits(token_id, friend) == 0
    assert pasanaku_contract.pool_escrow(token_id) == amount


def test_round_recipient_cannot_deposit(
    pasanaku_contract,
    usdc_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    _fund_round_deposit(
        usdc_contract,
        pasanaku_contract,
        owner,
        recipient,
        amount,
    )
    with boa.reverts(dev="active participant cannot deposit"):
        with boa.env.prank(recipient):
            pasanaku_contract.deposit_to_pasanaku(amount, token_id, recipient)


def test_duplicate_round_deposit_reverts(
    pasanaku_contract,
    usdc_contract,
    owner,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    amount = started_pasanaku["amount_raw"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    payer = next(user for user in started_pasanaku["users"] if user != recipient)
    _fund_round_deposit(
        usdc_contract,
        pasanaku_contract,
        owner,
        payer,
        amount * 2,
    )
    with boa.env.prank(payer):
        pasanaku_contract.deposit_to_pasanaku(amount, token_id, payer)
        with boa.reverts(dev="account already deposited"):
            pasanaku_contract.deposit_to_pasanaku(amount, token_id, payer)


def test_wrong_round_amount_reverts(
    pasanaku_contract,
    started_pasanaku,
):
    token_id = started_pasanaku["token_id"]
    recipient = pasanaku_contract.pasanaku(token_id).participants[0]
    payer = next(user for user in started_pasanaku["users"] if user != recipient)
    with boa.reverts(dev="invalid deposit amount"):
        with boa.env.prank(payer):
            pasanaku_contract.deposit_to_pasanaku(
                started_pasanaku["amount_raw"] - 1,
                token_id,
                payer,
            )
