import boa
from tests.conftest import (
    DAYS_30,
    PASANAKU_AMOUNT_RAW,
    fund_and_join_all,
    token_id_from_last_started,
)


def test_deploy_sets_supported_assets(
    pasanaku_contract, usdc_contract, usdt_contract, weth_contract, owner
):
    assets = pasanaku_contract.supported_assets()
    assert assets[0] == usdc_contract.address
    assert assets[1] == usdt_contract.address
    assert assets[2] == weth_contract.address
    assert pasanaku_contract.owner() == owner
    assert pasanaku_contract.participant_count() == 12


def test_deposit_without_pasanaku_id_updates_balance(
    pasanaku_contract, alice, owner, usdc_contract
):
    raw = 1_000 * 10**6
    with boa.env.prank(owner):
        usdc_contract.mint(alice, raw)
    with boa.env.prank(alice):
        usdc_contract.approve(pasanaku_contract.address, raw)
        pasanaku_contract.deposit(usdc_contract.address, raw, 0, 0)
    assert pasanaku_contract.deposited(alice, usdc_contract.address) == raw
    assert usdc_contract.balanceOf(pasanaku_contract.address) == raw


def test_deposit_zero_reverts(pasanaku_contract, alice, usdc_contract):
    with boa.reverts(dev="invalid amount"):
        with boa.env.prank(alice):
            pasanaku_contract.deposit(usdc_contract.address, 0, 0, 0)


def test_withdraw(pasanaku_contract, alice, owner, usdc_contract):
    raw = 500 * 10**6
    with boa.env.prank(owner):
        usdc_contract.mint(alice, raw)
    with boa.env.prank(alice):
        usdc_contract.approve(pasanaku_contract.address, raw)
        pasanaku_contract.deposit(usdc_contract.address, raw, 0, 0)
    with boa.env.prank(alice):
        pasanaku_contract.withdraw(usdc_contract.address, raw)
    assert pasanaku_contract.deposited(alice, usdc_contract.address) == 0
    assert usdc_contract.balanceOf(alice) == raw


def test_withdraw_zero_reverts(pasanaku_contract, alice, usdc_contract):
    with boa.reverts(dev="invalid amount"):
        with boa.env.prank(alice):
            pasanaku_contract.withdraw(usdc_contract.address, 0)


def test_withdraw_collateral_in_use_reverts(
    pasanaku_contract, owner, usdc_contract, twelve_users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    need = amount_raw * 12
    with boa.env.prank(owner):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )
    u0 = twelve_users[0]
    with boa.env.prank(owner):
        usdc_contract.mint(u0, need)
    with boa.env.prank(u0):
        usdc_contract.approve(pasanaku_contract.address, need)
        pasanaku_contract.deposit(usdc_contract.address, need, 0, 0)
    with boa.env.prank(u0):
        pasanaku_contract.join_pasanaku(pending_idx)
    with boa.reverts(dev="collateral in use"):
        with boa.env.prank(u0):
            pasanaku_contract.withdraw(usdc_contract.address, 1)


def test_withdraw_exceeds_free_reverts(pasanaku_contract, alice, owner, usdc_contract):
    raw = 100 * 10**6
    with boa.env.prank(owner):
        usdc_contract.mint(alice, raw)
    with boa.env.prank(alice):
        usdc_contract.approve(pasanaku_contract.address, raw)
        pasanaku_contract.deposit(usdc_contract.address, raw, 0, 0)
    with boa.reverts(dev="collateral in use"):
        with boa.env.prank(alice):
            pasanaku_contract.withdraw(usdc_contract.address, raw + 1)


def test_create_pasanaku_and_pending_view(pasanaku_contract, owner, usdc_contract):
    with boa.env.prank(owner):
        idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, PASANAKU_AMOUNT_RAW
        )
    assert idx == 0
    pending = pasanaku_contract.pending_pasanaku(idx)
    assert pending.asset == usdc_contract.address
    assert pending.amount == PASANAKU_AMOUNT_RAW


def test_create_pasanaku_unsupported_asset_reverts(pasanaku_contract, owner):
    fake = boa.env.generate_address()
    with boa.reverts(dev="unsupported asset"):
        with boa.env.prank(owner):
            pasanaku_contract.create_pasanaku(fake, PASANAKU_AMOUNT_RAW)


def test_join_pasanaku_invalid_index_reverts(
    pasanaku_contract, alice, owner, usdc_contract
):
    with boa.env.prank(owner):
        pasanaku_contract.create_pasanaku(usdc_contract.address, PASANAKU_AMOUNT_RAW)
    with boa.reverts(dev="invalid index"):
        with boa.env.prank(alice):
            pasanaku_contract.join_pasanaku(1)


def test_join_pasanaku_insufficient_collateral_reverts(
    pasanaku_contract, owner, usdc_contract, twelve_users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    need = amount_raw * 12
    with boa.env.prank(owner):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )

    u = twelve_users[0]
    with boa.env.prank(owner):
        usdc_contract.mint(u, need - 1)

    with boa.env.prank(u):
        usdc_contract.approve(pasanaku_contract.address, need - 1)
        pasanaku_contract.deposit(usdc_contract.address, need - 1, 0, 0)

    with boa.reverts(dev="insufficient collateral # nosplit"):
        with boa.env.prank(u):
            pasanaku_contract.join_pasanaku(pending_idx)


def test_join_eleven_does_not_start_pasanaku(
    pasanaku_contract, owner, usdc_contract, twelve_users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    with boa.env.prank(owner):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )
    fund_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        twelve_users[:11],
        amount_raw,
        pending_idx,
    )
    pending = pasanaku_contract.pending_pasanaku(pending_idx)
    assert len(pending.participants) == 11
    assert pending.started == 0


def test_join_pasanaku_duplicate_reverts(
    pasanaku_contract, owner, usdc_contract, twelve_users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    with boa.env.prank(owner):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )
    fund_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        twelve_users[:1],
        amount_raw,
        pending_idx,
    )
    with boa.reverts(dev="participant already joined # nosplit"):
        with boa.env.prank(twelve_users[0]):
            pasanaku_contract.join_pasanaku(pending_idx)


def test_full_join_starts_pasanaku_mints_and_clears_pending(
    pasanaku_contract, twelve_users, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    pidx = started_pasanaku["pending_idx"]
    pending = pasanaku_contract.pending_pasanaku(pidx)
    assert pending.asset == "0x0000000000000000000000000000000000000000"
    st = pasanaku_contract.pasanaku(tid)
    assert st.started != 0
    assert st.ended == 0
    for u in twelve_users:
        assert pasanaku_contract.balanceOf(u, tid) == 1


def test_tick_pays_participant_and_ends(
    pasanaku_contract, owner, usdc_contract, twelve_users, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    boa.env.time_travel(seconds=DAYS_30)
    pre = usdc_contract.balanceOf(users[0])
    pasanaku_contract.tick(tid)
    assert usdc_contract.balanceOf(users[0]) == pre + amount_raw
    st = pasanaku_contract.pasanaku(tid)
    assert st.updated != 0
    for i in range(1, 12):
        boa.env.time_travel(seconds=DAYS_30)
        pasanaku_contract.tick(tid)
    st = pasanaku_contract.pasanaku(tid)
    assert st.ended != 0


def test_tick_not_started_reverts(pasanaku_contract):
    with boa.reverts(dev="pasanaku not started"):
        pasanaku_contract.tick(999_999_999_999_999_999_999)


def test_tick_not_enough_time_reverts(pasanaku_contract, started_pasanaku):
    tid = started_pasanaku["token_id"]
    boa.env.time_travel(seconds=DAYS_30)
    pasanaku_contract.tick(tid)
    with boa.reverts(dev="not enough time passed # nosplit"):
        pasanaku_contract.tick(tid)


def test_tick_after_end_reverts(pasanaku_contract, started_pasanaku):
    tid = started_pasanaku["token_id"]
    for _ in range(12):
        boa.env.time_travel(seconds=DAYS_30)
        pasanaku_contract.tick(tid)
    with boa.reverts(dev="pasanaku ended"):
        boa.env.time_travel(seconds=DAYS_30)
        pasanaku_contract.tick(tid)


def test_deposit_for_tick_marks_deposited(
    pasanaku_contract, owner, usdc_contract, twelve_users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    with boa.env.prank(owner):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )
    fund_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        twelve_users,
        amount_raw,
        pending_idx,
    )
    tid = token_id_from_last_started(pasanaku_contract)
    u0 = twelve_users[0]
    extra = amount_raw
    with boa.env.prank(owner):
        usdc_contract.mint(u0, extra)
    with boa.env.prank(u0):
        usdc_contract.approve(pasanaku_contract.address, extra)
        pasanaku_contract.deposit(usdc_contract.address, extra, tid, 0)
    assert pasanaku_contract.deposited_for_token(tid, 0, u0) is True


def test_deposit_for_token_not_started_reverts(
    pasanaku_contract, alice, owner, usdc_contract
):
    raw = PASANAKU_AMOUNT_RAW * 12
    with boa.env.prank(owner):
        usdc_contract.mint(alice, raw)
    with boa.env.prank(alice):
        usdc_contract.approve(pasanaku_contract.address, raw)
        with boa.reverts(dev="pasanaku not started"):
            pasanaku_contract.deposit(
                usdc_contract.address, PASANAKU_AMOUNT_RAW, 12345, 0
            )


def test_deposit_for_token_not_participant_reverts(
    pasanaku_contract, owner, usdc_contract, twelve_users, alice
):
    amount_raw = PASANAKU_AMOUNT_RAW
    with boa.env.prank(owner):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )
    fund_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        twelve_users,
        amount_raw,
        pending_idx,
    )
    tid = token_id_from_last_started(pasanaku_contract)
    with boa.env.prank(owner):
        usdc_contract.mint(alice, amount_raw)
    with boa.env.prank(alice):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        with boa.reverts(dev="participant not in pasanaku # nosplit"):
            pasanaku_contract.deposit(usdc_contract.address, amount_raw, tid, 0)


def test_deposit_for_token_insufficient_amount_reverts(
    pasanaku_contract, owner, usdc_contract, twelve_users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    with boa.env.prank(owner):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )
    fund_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        twelve_users,
        amount_raw,
        pending_idx,
    )
    tid = token_id_from_last_started(pasanaku_contract)
    u0 = twelve_users[0]
    with boa.env.prank(owner):
        usdc_contract.mint(u0, amount_raw)
    with boa.env.prank(u0):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        with boa.reverts(dev="insufficient amount"):
            pasanaku_contract.deposit(usdc_contract.address, amount_raw - 1, tid, 0)


def test_deposit_for_token_twice_same_tick_reverts(
    pasanaku_contract, owner, usdc_contract, twelve_users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    with boa.env.prank(owner):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )
    fund_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        twelve_users,
        amount_raw,
        pending_idx,
    )
    tid = token_id_from_last_started(pasanaku_contract)
    u0 = twelve_users[0]
    extra = amount_raw * 2
    with boa.env.prank(owner):
        usdc_contract.mint(u0, extra)
    with boa.env.prank(u0):
        usdc_contract.approve(pasanaku_contract.address, extra)
        pasanaku_contract.deposit(usdc_contract.address, amount_raw, tid, 0)
        with boa.reverts(dev="already deposited # nosplit"):
            pasanaku_contract.deposit(usdc_contract.address, amount_raw, tid, 0)


def test_deposit_for_token_after_game_ended_reverts(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    u0 = started_pasanaku["users"][0]
    for _ in range(12):
        boa.env.time_travel(seconds=DAYS_30)
        pasanaku_contract.tick(tid)
    with boa.env.prank(owner):
        usdc_contract.mint(u0, amount_raw)
    with boa.env.prank(u0):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        with boa.reverts(dev="pasanaku ended"):
            pasanaku_contract.deposit(usdc_contract.address, amount_raw, tid, 0)


def test_collateral_in_use_view(pasanaku_contract, owner, usdc_contract, twelve_users):
    amount_raw = PASANAKU_AMOUNT_RAW
    need = amount_raw * 12
    with boa.env.prank(owner):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )
    u0 = twelve_users[0]
    with boa.env.prank(owner):
        usdc_contract.mint(u0, need)
    with boa.env.prank(u0):
        usdc_contract.approve(pasanaku_contract.address, need)
        pasanaku_contract.deposit(usdc_contract.address, need, 0, 0)
    assert pasanaku_contract.collateral_in_use(u0, usdc_contract.address) == 0
    with boa.env.prank(u0):
        pasanaku_contract.join_pasanaku(pending_idx)
    assert pasanaku_contract.collateral_in_use(u0, usdc_contract.address) == need
