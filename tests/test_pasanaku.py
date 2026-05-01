import boa

from tests.conftest import (
    DAYS_40,
    PASANAKU_AMOUNT_RAW,
    PARTICIPANT_COUNT,
    create_and_join_all,
    fund_collateral_for_users,
    penalty_per_amount,
    pledge,
    token_id_from_last_started,
)


def test_deploy_supported_assets_and_participant_count(
    pasanaku_contract, usdc_contract, usdt_contract, weth_contract, dai_contract
):
    assets = pasanaku_contract.supported_assets()
    assert assets[0] == usdc_contract.address
    assert assets[1] == usdt_contract.address
    assert assets[2] == weth_contract.address
    assert assets[3] == dai_contract.address
    assert pasanaku_contract.participant_count() == PARTICIPANT_COUNT


def test_create_pasanaku_returns_zero(
    pasanaku_contract, nine_users, owner, usdc_contract
):
    amount_raw = PASANAKU_AMOUNT_RAW
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [nine_users[0]], amount_raw
    )
    with boa.env.prank(nine_users[0]):
        idx = pasanaku_contract.create_pasanaku(usdc_contract.address, amount_raw)
    assert idx == 0


def test_join_insufficient_collateral_reverts(
    pasanaku_contract, owner, usdc_contract, nine_users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    need = pledge(amount_raw)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [nine_users[0]], amount_raw
    )
    with boa.env.prank(nine_users[0]):
        pending_idx = pasanaku_contract.create_pasanaku(
            usdc_contract.address, amount_raw
        )

    u = nine_users[1]
    with boa.env.prank(owner):
        usdc_contract.mint(u, need - 1)
    with boa.env.prank(u):
        usdc_contract.approve(pasanaku_contract.address, need - 1)
        pasanaku_contract.add_collateral(usdc_contract.address, need - 1)
    with boa.reverts(dev="insufficient collateral # nosplit"):
        with boa.env.prank(u):
            pasanaku_contract.join_pasanaku(pending_idx)


def test_join_duplicate_reverts(pasanaku_contract, owner, usdc_contract, nine_users):
    amount_raw = PASANAKU_AMOUNT_RAW
    create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        nine_users[:2],
        amount_raw,
    )
    pending_idx = 0
    with boa.reverts(dev="participant already joined # nosplit"):
        with boa.env.prank(nine_users[0]):
            pasanaku_contract.join_pasanaku(pending_idx)


def test_full_join_starts_pasanaku(pasanaku_contract, owner, usdc_contract, nine_users):
    amount_raw = PASANAKU_AMOUNT_RAW
    create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        nine_users,
        amount_raw,
    )
    tid = token_id_from_last_started(pasanaku_contract)
    st = pasanaku_contract.pasanaku(tid)
    assert st.started != 0
    assert st.ended == 0


def test_collateral_in_use_after_join(
    pasanaku_contract, owner, usdc_contract, nine_users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    need = pledge(amount_raw)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, nine_users[:2], amount_raw
    )
    with boa.env.prank(nine_users[0]):
        pasanaku_contract.create_pasanaku(usdc_contract.address, amount_raw)
    assert (
        pasanaku_contract.collateral_in_use(nine_users[0], usdc_contract.address)
        == need
    )
    with boa.env.prank(nine_users[1]):
        pasanaku_contract.join_pasanaku(0)
    assert (
        pasanaku_contract.collateral_in_use(nine_users[1], usdc_contract.address)
        == need
    )


def test_withdraw_collateral_blocked_when_all_locked(
    pasanaku_contract, owner, usdc_contract, nine_users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [nine_users[0]], amount_raw
    )
    with boa.env.prank(nine_users[0]):
        pasanaku_contract.create_pasanaku(usdc_contract.address, amount_raw)
    with boa.reverts(dev="collateral in use"):
        with boa.env.prank(nine_users[0]):
            pasanaku_contract.withdraw_collateral(usdc_contract.address, 1)


def test_tick_first_pays_principal_only(
    pasanaku_contract, owner, usdc_contract, nine_users, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    owner_pre = usdc_contract.balanceOf(owner)

    for u in users[1:]:
        with boa.env.prank(owner):
            usdc_contract.mint(u, amount_raw)
        with boa.env.prank(u):
            usdc_contract.approve(pasanaku_contract.address, amount_raw)
            pasanaku_contract.deposit_to_pasanaku(
                usdc_contract.address, amount_raw, tid
            )

    boa.env.time_travel(seconds=DAYS_40)
    recipient = users[0]
    pre_recipient = usdc_contract.balanceOf(recipient)
    pasanaku_contract.tick(tid)

    expected = amount_raw * (PARTICIPANT_COUNT - 1)
    assert usdc_contract.balanceOf(recipient) == pre_recipient + expected
    assert usdc_contract.balanceOf(owner) == owner_pre

    st = pasanaku_contract.pasanaku(tid)
    assert st.index == 1


def test_recipient_cannot_deposit(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    recipient = started_pasanaku["users"][0]
    with boa.env.prank(owner):
        usdc_contract.mint(recipient, amount_raw)
    with boa.env.prank(recipient):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        with boa.reverts(dev="active participant cannot deposit # nosplit"):
            pasanaku_contract.deposit_to_pasanaku(
                usdc_contract.address, amount_raw, tid
            )


def test_middle_tick(
    pasanaku_contract, owner, usdc_contract, nine_users, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    for round_idx in range(5):
        recipient = users[round_idx]
        for u in users:
            if u == recipient:
                continue
            with boa.env.prank(owner):
                usdc_contract.mint(u, amount_raw)
            with boa.env.prank(u):
                usdc_contract.approve(pasanaku_contract.address, amount_raw)
                pasanaku_contract.deposit_to_pasanaku(
                    usdc_contract.address, amount_raw, tid
                )
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(tid)

    st = pasanaku_contract.pasanaku(tid)
    assert st.index == 5


def test_last_tick_ends_and_uri(
    pasanaku_contract, owner, usdc_contract, nine_users, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    for round_idx in range(PARTICIPANT_COUNT):
        recipient = users[round_idx]
        for u in users:
            if u == recipient:
                continue
            with boa.env.prank(owner):
                usdc_contract.mint(u, amount_raw)
            with boa.env.prank(u):
                usdc_contract.approve(pasanaku_contract.address, amount_raw)
                pasanaku_contract.deposit_to_pasanaku(
                    usdc_contract.address, amount_raw, tid
                )
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(tid)

    st = pasanaku_contract.pasanaku(tid)
    assert st.ended != 0
    assert st.index == PARTICIPANT_COUNT
    assert pasanaku_contract.uri(tid) == "https://pasanaku.fun/pasanaku/ended"


def test_non_payer_slash_penalty_to_owner_not_eligibles(
    pasanaku_contract, owner, usdc_contract, nine_users, started_pasanaku
):
    """Single defaulter: full penalty_pool goes to owner(); eligibles' USDC unchanged by penalty."""
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    defaulter = users[1]
    recipient = users[0]

    for u in users:
        if u == recipient or u == defaulter:
            continue
        with boa.env.prank(owner):
            usdc_contract.mint(u, amount_raw)
        with boa.env.prank(u):
            usdc_contract.approve(pasanaku_contract.address, amount_raw)
            pasanaku_contract.deposit_to_pasanaku(
                usdc_contract.address, amount_raw, tid
            )
            assert pasanaku_contract.successful_obligated_deposits(tid, u) == 1

    slash_total = amount_raw + penalty_per_amount(amount_raw)
    pre_collateral = pasanaku_contract.collateral(defaulter, usdc_contract.address)
    owner_pre = usdc_contract.balanceOf(owner)

    boa.env.time_travel(seconds=DAYS_40)
    pre_recipient = usdc_contract.balanceOf(recipient)
    eligible = [u for u in users if u != recipient and u != defaulter]
    pre_pay = sum(usdc_contract.balanceOf(u) for u in eligible)
    pasanaku_contract.tick(tid)

    pen = penalty_per_amount(amount_raw)
    assert usdc_contract.balanceOf(recipient) == pre_recipient + amount_raw * (
        PARTICIPANT_COUNT - 1
    )
    assert usdc_contract.balanceOf(owner) == owner_pre + pen
    assert (
        pasanaku_contract.collateral(defaulter, usdc_contract.address)
        == pre_collateral - slash_total
    )

    post_pay = sum(usdc_contract.balanceOf(u) for u in eligible)
    assert post_pay == pre_pay


def test_happy_path_collateral_in_use_zero_after_end(
    pasanaku_contract, owner, usdc_contract, nine_users, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    for round_idx in range(PARTICIPANT_COUNT):
        recipient = users[round_idx]
        for u in users:
            if u == recipient:
                continue
            with boa.env.prank(owner):
                usdc_contract.mint(u, amount_raw)
            with boa.env.prank(u):
                usdc_contract.approve(pasanaku_contract.address, amount_raw)
                pasanaku_contract.deposit_to_pasanaku(
                    usdc_contract.address, amount_raw, tid
                )
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(tid)

    for u in users:
        assert pasanaku_contract.collateral_in_use(u, usdc_contract.address) == 0


def test_duplicate_deposit_same_round_reverts(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    payer = started_pasanaku["users"][1]
    extra = amount_raw * 2
    with boa.env.prank(owner):
        usdc_contract.mint(payer, extra)
    with boa.env.prank(payer):
        usdc_contract.approve(pasanaku_contract.address, extra)
        pasanaku_contract.deposit_to_pasanaku(usdc_contract.address, amount_raw, tid)
        with boa.reverts(dev="account already deposited # nosplit"):
            pasanaku_contract.deposit_to_pasanaku(
                usdc_contract.address, amount_raw, tid
            )


def test_deposit_wrong_amount_reverts(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    payer = started_pasanaku["users"][1]
    with boa.env.prank(owner):
        usdc_contract.mint(payer, amount_raw)
    with boa.env.prank(payer):
        usdc_contract.approve(pasanaku_contract.address, amount_raw)
        with boa.reverts(dev="invalid deposit amount"):
            pasanaku_contract.deposit_to_pasanaku(
                usdc_contract.address, amount_raw - 1, tid
            )


def test_all_obligated_nonrecipients_default_penalty_to_owner(
    pasanaku_contract, owner, usdc_contract, nine_users, started_pasanaku
):
    """Nobody deposits; recipient exempt — no eligible depositor; full penalty_pool to owner()."""
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    owner_pre = usdc_contract.balanceOf(owner)
    pen_total = penalty_per_amount(amount_raw) * (PARTICIPANT_COUNT - 1)

    boa.env.time_travel(seconds=DAYS_40)
    pasanaku_contract.tick(tid)

    assert usdc_contract.balanceOf(owner) == owner_pre + pen_total
    recipient = users[0]
    for u in users:
        if u == recipient:
            continue
        assert pasanaku_contract.successful_obligated_deposits(tid, u) == 0


def test_penalties_all_to_owner_when_eligibles_exist(
    pasanaku_contract, owner, usdc_contract, nine_users, started_pasanaku
):
    """Round 0 all obligors pay; round 1 one defaulter — full penalty on that round to owner()."""
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    for round_idx in range(2):
        recipient = users[round_idx]
        for u in users:
            if u == recipient:
                continue
            if round_idx == 1 and u == users[2]:
                continue
            with boa.env.prank(owner):
                usdc_contract.mint(u, amount_raw)
            with boa.env.prank(u):
                usdc_contract.approve(pasanaku_contract.address, amount_raw)
                pasanaku_contract.deposit_to_pasanaku(
                    usdc_contract.address, amount_raw, tid
                )
        boa.env.time_travel(seconds=DAYS_40)
        if round_idx == 0:
            pasanaku_contract.tick(tid)

    pen = penalty_per_amount(amount_raw)
    owner_pre = usdc_contract.balanceOf(owner)
    pasanaku_contract.tick(tid)

    assert usdc_contract.balanceOf(owner) == owner_pre + pen


def test_accept_ownership(pasanaku_contract, owner, alice):
    assert pasanaku_contract.owner() == owner
    with boa.env.prank(owner):
        pasanaku_contract.transfer_ownership(alice)
    assert pasanaku_contract.pending_owner() == alice
    with boa.env.prank(alice):
        pasanaku_contract.accept_ownership()
    assert pasanaku_contract.owner() == alice


def test_harvest_yield_splits_surplus_after_pool_ends(
    pasanaku_contract,
    owner,
    usdc_contract,
    fluid_ftokens,
    nine_users,
    started_pasanaku,
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    ft_usdc = fluid_ftokens[0]

    for round_idx in range(PARTICIPANT_COUNT):
        recipient = users[round_idx]
        for u in users:
            if u == recipient:
                continue
            with boa.env.prank(owner):
                usdc_contract.mint(u, amount_raw)
            with boa.env.prank(u):
                usdc_contract.approve(pasanaku_contract.address, amount_raw)
                pasanaku_contract.deposit_to_pasanaku(
                    usdc_contract.address, amount_raw, tid
                )
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(tid)

    assert pasanaku_contract.fluid_principal_tracked(tid) == 0

    yield_amt = 1_000_000
    with boa.env.prank(owner):
        usdc_contract.mint(owner, yield_amt)
        usdc_contract.approve(ft_usdc.address, yield_amt)
        ft_usdc.deposit(yield_amt, pasanaku_contract.address)

    surplus = yield_amt
    treasury_base = surplus * 2500 // 10_000
    late_pool = surplus - treasury_base
    per = late_pool // 6
    dust = surplus - treasury_base - per * 6
    owner_amt = treasury_base + dust

    pre_late = [usdc_contract.balanceOf(users[i]) for i in range(3, 9)]
    pre_owner = usdc_contract.balanceOf(owner)

    with boa.env.prank(owner):
        pasanaku_contract.harvest_yield(tid)

    for i in range(3, 9):
        assert usdc_contract.balanceOf(users[i]) == pre_late[i - 3] + per
    assert usdc_contract.balanceOf(owner) == pre_owner + owner_amt
