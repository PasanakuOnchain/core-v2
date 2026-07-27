import boa

from tests.utils.constants import (
    BPS_PRECISION,
    DAYS_40,
    MISS_PENALTY_BPS,
    PARTICIPANT_COUNT,
)


def pledge(amount_raw: int, participant_count: int = PARTICIPANT_COUNT) -> int:
    principal = amount_raw * participant_count
    return principal + principal * MISS_PENALTY_BPS // BPS_PRECISION


def penalty_per_amount(amount_raw: int) -> int:
    return amount_raw * MISS_PENALTY_BPS // BPS_PRECISION


def create_pasanaku(
    pasanaku_contract,
    amount_raw,
    participant_count=PARTICIPANT_COUNT,
    *,
    value=None,
):
    fee = pasanaku_contract.fee() if value is None else value
    return pasanaku_contract.create_pasanaku(
        amount_raw,
        participant_count,
        value=fee,
    )


def fund_collateral_for_users(
    pasanaku_contract,
    asset,
    owner,
    users,
    amount_raw,
    participant_count=PARTICIPANT_COUNT,
    *,
    raw=False,
):
    assets = amount_raw if raw else pledge(amount_raw, participant_count)
    for user in users:
        with boa.env.prank(owner):
            asset.mint(user, assets)
        with boa.env.prank(user):
            asset.approve(pasanaku_contract.address, assets)
            pasanaku_contract.deposit(assets, user)


def create_and_join_all(
    pasanaku_contract,
    asset,
    owner,
    users,
    amount_raw,
    participant_count=PARTICIPANT_COUNT,
):
    assert len(users) == participant_count
    fund_collateral_for_users(
        pasanaku_contract,
        asset,
        owner,
        users,
        amount_raw,
        participant_count,
    )
    with boa.env.prank(users[0]):
        token_id = create_pasanaku(
            pasanaku_contract,
            amount_raw,
            participant_count,
        )
    for user in users[1:]:
        with boa.env.prank(user):
            pasanaku_contract.join_pasanaku(token_id)
    return token_id


def deposit_all_obligors(
    pasanaku_contract,
    token_id,
    users,
    round_idx,
    asset,
    owner,
    amount_raw,
):
    recipient = pasanaku_contract.pasanaku(token_id).participants[round_idx]
    for user in users:
        if user == recipient:
            continue
        with boa.env.prank(owner):
            asset.mint(user, amount_raw)
        with boa.env.prank(user):
            asset.approve(pasanaku_contract.address, amount_raw)
            pasanaku_contract.deposit_to_pasanaku(amount_raw, token_id)


def tick_and_claim(pasanaku_contract, token_id, round_idx, users):
    pasanaku_contract.tick(token_id)
    recipient = pasanaku_contract.pasanaku(token_id).participants[round_idx]
    with boa.env.prank(recipient):
        pasanaku_contract.claim_round_payout(token_id, round_idx)


def run_all_rounds(
    pasanaku_contract,
    token_id,
    users,
    asset,
    owner,
    amount_raw,
):
    for round_idx in range(len(users)):
        deposit_all_obligors(
            pasanaku_contract,
            token_id,
            users,
            round_idx,
            asset,
            owner,
            amount_raw,
        )
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(token_id)


def donate_yield(vault, asset, owner, amount):
    with boa.env.prank(owner):
        asset.approve(vault.address, amount)
        vault.donate(amount)


def generate_users(count: int):
    users = []
    for index in range(count):
        addr = boa.env.generate_address(alias=f"generated-participant-{index}")
        boa.env.set_balance(addr, 10**18)
        users.append(addr)
    return users
