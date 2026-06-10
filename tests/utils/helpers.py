import boa

from tests.utils.constants import BPS_PRECISION, MISS_PENALTY_BPS, PARTICIPANT_COUNT


def pledge(amount_raw: int) -> int:
    return (
        amount_raw * PARTICIPANT_COUNT
        + amount_raw * PARTICIPANT_COUNT * MISS_PENALTY_BPS // BPS_PRECISION
    )


def penalty_per_amount(amount_raw: int) -> int:
    return amount_raw * MISS_PENALTY_BPS // BPS_PRECISION


def tick_and_claim(pasanaku_contract, token_id, round_idx, users):
    pasanaku_contract.tick(token_id)
    recipient = users[round_idx]
    with boa.env.prank(recipient):
        pasanaku_contract.claim_round_payout(token_id, round_idx)


def token_id_from_last_started(pasanaku_contract):
    """Read token_id from PasanakuStarted in the most recent transaction logs."""
    for log in reversed(pasanaku_contract.get_logs()):
        if type(log).__name__ == "PasanakuStarted":
            return log.token_id
    raise RuntimeError("PasanakuStarted log not found")


def logs_from_last_tx(pasanaku_contract):
    """Return event logs emitted by the contract's most recent transaction."""
    return pasanaku_contract.get_logs()


def create_pasanaku(pasanaku_contract, asset_address, amount_raw, *, value=None):
    fee = pasanaku_contract.fee() if value is None else value
    return pasanaku_contract.create_pasanaku(asset_address, amount_raw, value=fee)


def fund_collateral_for_users(
    pasanaku_contract, asset, owner, users, amount_raw, raw=False
):
    need = amount_raw if raw else pledge(amount_raw)
    for u in users:
        with boa.env.prank(owner):
            asset.mint(u, need)
        with boa.env.prank(u):
            asset.approve(pasanaku_contract.address, need)
            pasanaku_contract.add_collateral(asset.address, need)


def create_and_join_all(pasanaku_contract, asset, owner, users, amount_raw):
    fund_collateral_for_users(pasanaku_contract, asset, owner, users, amount_raw)
    with boa.env.prank(users[0]):
        pending_idx = create_pasanaku(pasanaku_contract, asset.address, amount_raw)
    for u in users[1:]:
        with boa.env.prank(u):
            pasanaku_contract.join_pasanaku(pending_idx)
    return pending_idx


def deposit_all_obligors(
    pasanaku_contract, token_id, users, round_idx, asset, owner, amount_raw
):
    recipient = users[round_idx]
    for u in users:
        if u == recipient:
            continue
        with boa.env.prank(owner):
            asset.mint(u, amount_raw)
        with boa.env.prank(u):
            asset.approve(pasanaku_contract.address, amount_raw)
            pasanaku_contract.deposit_to_pasanaku(amount_raw, token_id)


def run_all_rounds(pasanaku_contract, token_id, users, asset, owner, amount_raw):
    for round_idx in range(PARTICIPANT_COUNT):
        deposit_all_obligors(
            pasanaku_contract, token_id, users, round_idx, asset, owner, amount_raw
        )
        boa.env.time_travel(seconds=40 * 24 * 60 * 60)
        pasanaku_contract.tick(token_id)


def generate_users(count: int):
    addrs = []
    for _ in range(count):
        addr = boa.env.generate_address()
        boa.env.set_balance(addr, 10**18)
        addrs.append(addr)
    return addrs
