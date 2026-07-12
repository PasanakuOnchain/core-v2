import boa

from tests.utils.constants import DAYS_40, PARTICIPANT_COUNT, URI_ENDED
from tests.utils.helpers import (
    deposit_all_obligors,
    penalty_per_amount,
    tick_and_claim,
)


def test_tick_first_pays_principal_only(
    pasanaku_contract, owner, usdc_contract, users, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    owner_pre = usdc_contract.balanceOf(owner)

    deposit_all_obligors(
        pasanaku_contract, tid, users, 0, usdc_contract, owner, amount_raw
    )

    boa.env.time_travel(seconds=DAYS_40)
    recipient = users[0]
    pre_recipient = usdc_contract.balanceOf(recipient)
    tick_and_claim(pasanaku_contract, tid, 0, users)

    expected = amount_raw * (PARTICIPANT_COUNT - 1)
    assert usdc_contract.balanceOf(recipient) == pre_recipient + expected
    assert usdc_contract.balanceOf(owner) == owner_pre

    st = pasanaku_contract.pasanaku(tid)
    assert st.index == 1


def test_tick_too_early_reverts(pasanaku_contract, started_pasanaku):
    tid = started_pasanaku["token_id"]
    with boa.reverts(dev="not enough time passed # nosplit"):
        pasanaku_contract.tick(tid)


def test_tick_invalid_token_id_reverts(pasanaku_contract):
    with boa.reverts(dev="pasanaku not started"):
        pasanaku_contract.tick(999)


def test_tick_emits_pasanaku_ticked(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    deposit_all_obligors(
        pasanaku_contract, tid, users, 0, usdc_contract, owner, amount_raw
    )
    boa.env.time_travel(seconds=DAYS_40)
    pasanaku_contract.tick(tid)

    ticked = [
        log
        for log in pasanaku_contract.get_logs()
        if type(log).__name__ == "PasanakuTicked"
    ]
    assert len(ticked) == 1
    assert ticked[0].token_id == tid
    assert ticked[0].tick_index == 0
    assert ticked[0].recipient == users[0]
    assert ticked[0].amount == amount_raw * (PARTICIPANT_COUNT - 1)


def test_middle_tick(pasanaku_contract, owner, usdc_contract, users, started_pasanaku):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    for round_idx in range(5):
        deposit_all_obligors(
            pasanaku_contract, tid, users, round_idx, usdc_contract, owner, amount_raw
        )
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(tid)

    st = pasanaku_contract.pasanaku(tid)
    assert st.index == 5


def test_last_tick_ends_and_uri(
    pasanaku_contract, owner, usdc_contract, users, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    for round_idx in range(PARTICIPANT_COUNT):
        deposit_all_obligors(
            pasanaku_contract, tid, users, round_idx, usdc_contract, owner, amount_raw
        )
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(tid)
        if round_idx == PARTICIPANT_COUNT - 1:
            ended = [
                log
                for log in pasanaku_contract.get_logs()
                if type(log).__name__ == "PasanakuEnded"
            ]

    st = pasanaku_contract.pasanaku(tid)
    assert st.ended != 0
    assert st.index == PARTICIPANT_COUNT
    assert pasanaku_contract.uri(tid) == URI_ENDED

    assert len(ended) == 1
    assert ended[0].token_id == tid


def test_non_payer_slash_penalty_to_owner_not_eligibles(
    pasanaku_contract, owner, usdc_contract, users, started_pasanaku
):
    """Single defaulter: penalties accrue then claim_penalties pays owner(); eligibles unchanged."""
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    defaulter = users[1]
    recipient = users[0]
    asset = usdc_contract.address

    for u in users:
        if u == recipient or u == defaulter:
            continue
        with boa.env.prank(owner):
            usdc_contract.mint(u, amount_raw)
        with boa.env.prank(u):
            usdc_contract.approve(pasanaku_contract.address, amount_raw)
            pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)
            assert pasanaku_contract.successful_obligated_deposits(tid, u) == 1

    slash_total = amount_raw + penalty_per_amount(amount_raw)
    pre_collateral = pasanaku_contract.collateral(defaulter, usdc_contract.address)
    owner_pre = usdc_contract.balanceOf(owner)

    boa.env.time_travel(seconds=DAYS_40)
    pre_recipient = usdc_contract.balanceOf(recipient)
    eligible = [u for u in users if u != recipient and u != defaulter]
    pre_pay = sum(usdc_contract.balanceOf(u) for u in eligible)
    pasanaku_contract.tick(tid)
    tick_logs = pasanaku_contract.get_logs()
    pen = penalty_per_amount(amount_raw)
    penalties = [log for log in tick_logs if type(log).__name__ == "PasanakuPenalties"]
    assert len(penalties) == 1
    assert penalties[0].amount == pen

    assert usdc_contract.balanceOf(owner) == owner_pre
    assert pasanaku_contract.pending_penalties(asset) == pen

    assert usdc_contract.balanceOf(recipient) == pre_recipient  # claim not yet called
    assert pasanaku_contract.pending_payout(tid, 0) == amount_raw * (
        PARTICIPANT_COUNT - 1
    )

    with boa.env.prank(recipient):
        pasanaku_contract.claim_round_payout(tid, 0)

    assert usdc_contract.balanceOf(recipient) == pre_recipient + amount_raw * (
        PARTICIPANT_COUNT - 1
    )
    pasanaku_contract.claim_penalties(asset)
    assert usdc_contract.balanceOf(owner) == owner_pre + pen
    assert pasanaku_contract.pending_penalties(asset) == 0
    assert (
        pasanaku_contract.collateral(defaulter, usdc_contract.address)
        == pre_collateral - slash_total
    )

    post_pay = sum(usdc_contract.balanceOf(u) for u in eligible)
    assert post_pay == pre_pay


def test_happy_path_collateral_in_use_zero_after_end(
    pasanaku_contract, owner, usdc_contract, users, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    for round_idx in range(PARTICIPANT_COUNT):
        deposit_all_obligors(
            pasanaku_contract, tid, users, round_idx, usdc_contract, owner, amount_raw
        )
        boa.env.time_travel(seconds=DAYS_40)
        pasanaku_contract.tick(tid)

    for u in users:
        assert pasanaku_contract.collateral_in_use(u, usdc_contract.address) == 0


def test_all_obligated_nonrecipients_default_penalty_to_owner(
    pasanaku_contract, owner, usdc_contract, users, started_pasanaku
):
    """Nobody deposits; recipient exempt — full penalty_pool accrues then claimable by owner."""
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    asset = usdc_contract.address
    owner_pre = usdc_contract.balanceOf(owner)
    pen_total = penalty_per_amount(amount_raw) * (PARTICIPANT_COUNT - 1)
    expected_payout = amount_raw * (PARTICIPANT_COUNT - 1)

    boa.env.time_travel(seconds=DAYS_40)
    pasanaku_contract.tick(tid)

    assert usdc_contract.balanceOf(owner) == owner_pre
    assert pasanaku_contract.pending_penalties(asset) == pen_total
    pasanaku_contract.claim_penalties(asset)
    assert usdc_contract.balanceOf(owner) == owner_pre + pen_total
    assert pasanaku_contract.pending_penalties(asset) == 0
    assert pasanaku_contract.pending_payout(tid, 0) == expected_payout
    recipient = users[0]
    for u in users:
        if u == recipient:
            continue
        assert pasanaku_contract.successful_obligated_deposits(tid, u) == 0


def test_penalties_all_to_owner_when_eligibles_exist(
    pasanaku_contract, owner, usdc_contract, users, started_pasanaku
):
    """Round 0 all obligors pay; round 1 one defaulter — penalty accrues then claimable."""
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    asset = usdc_contract.address

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
                pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)
        boa.env.time_travel(seconds=DAYS_40)
        if round_idx == 0:
            pasanaku_contract.tick(tid)

    pen = penalty_per_amount(amount_raw)
    owner_pre = usdc_contract.balanceOf(owner)
    pasanaku_contract.tick(tid)

    assert usdc_contract.balanceOf(owner) == owner_pre
    assert pasanaku_contract.pending_penalties(asset) == pen
    pasanaku_contract.claim_penalties(asset)
    assert usdc_contract.balanceOf(owner) == owner_pre + pen
    assert pasanaku_contract.pending_penalties(asset) == 0


def test_tick_decreases_contract_escrow_by_payout(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    deposit_all_obligors(
        pasanaku_contract, tid, users, 0, usdc_contract, owner, amount_raw
    )

    expected_payout = amount_raw * (PARTICIPANT_COUNT - 1)
    pre_escrow = usdc_contract.balanceOf(pasanaku_contract.address)

    boa.env.time_travel(seconds=DAYS_40)
    tick_and_claim(pasanaku_contract, tid, 0, users)

    assert (
        usdc_contract.balanceOf(pasanaku_contract.address)
        == pre_escrow - expected_payout
    )


def test_pool_escrow_tracks_deposits_and_slashes(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]

    assert pasanaku_contract.pool_escrow(tid) == 0

    deposit_all_obligors(
        pasanaku_contract, tid, users, 0, usdc_contract, owner, amount_raw
    )

    assert pasanaku_contract.pool_escrow(tid) == amount_raw * (PARTICIPANT_COUNT - 1)

    boa.env.time_travel(seconds=DAYS_40)
    tick_and_claim(pasanaku_contract, tid, 0, users)

    assert pasanaku_contract.pool_escrow(tid) == 0

    boa.env.time_travel(seconds=DAYS_40)
    pasanaku_contract.tick(tid)

    expected_payout = amount_raw * (PARTICIPANT_COUNT - 1)
    assert pasanaku_contract.pending_payout(tid, 1) == expected_payout
    assert pasanaku_contract.pool_escrow(tid) == 0


def test_penalty_transfer_reaches_owner(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    defaulter = users[1]
    recipient = users[0]
    asset = usdc_contract.address

    for u in users:
        if u == recipient or u == defaulter:
            continue
        with boa.env.prank(owner):
            usdc_contract.mint(u, amount_raw)
        with boa.env.prank(u):
            usdc_contract.approve(pasanaku_contract.address, amount_raw)
            pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)

    owner_pre = usdc_contract.balanceOf(owner)
    boa.env.time_travel(seconds=DAYS_40)
    tick_and_claim(pasanaku_contract, tid, 0, users)

    pen = penalty_per_amount(amount_raw)
    assert usdc_contract.balanceOf(owner) == owner_pre
    assert pasanaku_contract.pending_penalties(asset) == pen
    pasanaku_contract.claim_penalties(asset)
    assert usdc_contract.balanceOf(owner) == owner_pre + pen
    assert pasanaku_contract.pending_penalties(asset) == 0


def test_tick_with_miss_succeeds_after_renounce_ownership(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    """After renounce, miss penalties accrue without freezing tick; claim to zero may fail."""
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    defaulter = users[1]
    recipient = users[0]
    asset = usdc_contract.address

    for u in users:
        if u == recipient or u == defaulter:
            continue
        with boa.env.prank(owner):
            usdc_contract.mint(u, amount_raw)
        with boa.env.prank(u):
            usdc_contract.approve(pasanaku_contract.address, amount_raw)
            pasanaku_contract.deposit_to_pasanaku(amount_raw, tid)

    with boa.env.prank(owner):
        pasanaku_contract.renounce_ownership()

    boa.env.time_travel(seconds=DAYS_40)
    pasanaku_contract.tick(tid)

    st = pasanaku_contract.pasanaku(tid)
    assert st.index == 1
    pen = penalty_per_amount(amount_raw)
    assert pasanaku_contract.pending_penalties(asset) == pen

    with boa.reverts():
        pasanaku_contract.claim_penalties(asset)

    assert pasanaku_contract.pending_penalties(asset) == pen
    assert st.index == 1


def test_tick_advances_without_claim(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    recipient = users[0]

    deposit_all_obligors(
        pasanaku_contract, tid, users, 0, usdc_contract, owner, amount_raw
    )

    pre_recipient = usdc_contract.balanceOf(recipient)
    boa.env.time_travel(seconds=DAYS_40)
    pasanaku_contract.tick(tid)

    expected = amount_raw * (PARTICIPANT_COUNT - 1)
    assert pasanaku_contract.pending_payout(tid, 0) == expected
    assert usdc_contract.balanceOf(recipient) == pre_recipient
    st = pasanaku_contract.pasanaku(tid)
    assert st.index == 1


def test_claim_round_payout_only_recipient(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    non_recipient = users[1]

    deposit_all_obligors(
        pasanaku_contract, tid, users, 0, usdc_contract, owner, amount_raw
    )

    boa.env.time_travel(seconds=DAYS_40)
    pasanaku_contract.tick(tid)

    with boa.reverts():
        with boa.env.prank(non_recipient):
            pasanaku_contract.claim_round_payout(tid, 0)


def test_claim_round_payout_zero_pending_reverts(pasanaku_contract, started_pasanaku):
    tid = started_pasanaku["token_id"]
    recipient = started_pasanaku["users"][0]
    with boa.reverts():
        with boa.env.prank(recipient):
            pasanaku_contract.claim_round_payout(tid, 0)


def test_claim_round_payout_pays_recipient(
    pasanaku_contract, owner, usdc_contract, started_pasanaku
):
    tid = started_pasanaku["token_id"]
    amount_raw = started_pasanaku["amount_raw"]
    users = started_pasanaku["users"]
    recipient = users[0]

    deposit_all_obligors(
        pasanaku_contract, tid, users, 0, usdc_contract, owner, amount_raw
    )

    boa.env.time_travel(seconds=DAYS_40)
    pasanaku_contract.tick(tid)

    pre_recipient = usdc_contract.balanceOf(recipient)
    expected = amount_raw * (PARTICIPANT_COUNT - 1)
    with boa.env.prank(recipient):
        pasanaku_contract.claim_round_payout(tid, 0)

    assert usdc_contract.balanceOf(recipient) == pre_recipient + expected
    assert pasanaku_contract.pending_payout(tid, 0) == 0
