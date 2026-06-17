import boa

from tests.utils.constants import (
    DAYS_3,
    DAYS_40,
    PARTICIPANT_COUNT,
    PASANAKU_AMOUNT_RAW,
)
from tests.utils.helpers import (
    create_and_join_all,
    create_pasanaku,
    fund_collateral_for_users,
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


def test_create_first_pasanaku_returns_zero(
    pasanaku_contract, users, owner, usdc_contract
):
    amount_raw = PASANAKU_AMOUNT_RAW
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [users[0]], amount_raw
    )
    with boa.env.prank(users[0]):
        idx = create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)
    assert idx == 0


def test_create_pasanaku_emits_event(pasanaku_contract, owner, usdc_contract, users):
    amount_raw = PASANAKU_AMOUNT_RAW
    creator = users[0]
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [creator], amount_raw
    )
    with boa.env.prank(creator):
        token_id = create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)

    created = [
        log
        for log in pasanaku_contract.get_logs()
        if type(log).__name__ == "PasanakuCreated"
    ]
    assert len(created) == 1
    assert created[0].token_id == token_id
    assert created[0].asset == usdc_contract.address
    assert created[0].amount == amount_raw


def test_create_insufficient_collateral_reverts(
    pasanaku_contract, owner, usdc_contract, users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    need = pledge(amount_raw)
    creator = users[0]
    with boa.env.prank(owner):
        usdc_contract.mint(creator, need - 1)
    with boa.env.prank(creator):
        usdc_contract.approve(pasanaku_contract.address, need - 1)
        pasanaku_contract.add_collateral(usdc_contract.address, need - 1)
    with boa.reverts(dev="insufficient collateral # nosplit"):
        with boa.env.prank(creator):
            create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)


def test_create_unsupported_asset_reverts(pasanaku_contract, users):
    fake_asset = boa.env.generate_address()
    with boa.reverts(dev="unsupported asset"):
        with boa.env.prank(users[0]):
            create_pasanaku(pasanaku_contract, fake_asset, PASANAKU_AMOUNT_RAW)


def test_create_zero_amount_reverts(pasanaku_contract, users, usdc_contract):
    with boa.reverts(dev="invalid amount"):
        with boa.env.prank(users[0]):
            create_pasanaku(pasanaku_contract, usdc_contract.address, 0)


def test_join_insufficient_collateral_reverts(
    pasanaku_contract, owner, usdc_contract, users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    need = pledge(amount_raw)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, [users[0]], amount_raw
    )
    with boa.env.prank(users[0]):
        pending_idx = create_pasanaku(
            pasanaku_contract, usdc_contract.address, amount_raw
        )

    u = users[1]
    with boa.env.prank(owner):
        usdc_contract.mint(u, need - 1)
    with boa.env.prank(u):
        usdc_contract.approve(pasanaku_contract.address, need - 1)
        pasanaku_contract.add_collateral(usdc_contract.address, need - 1)
    with boa.reverts(dev="insufficient collateral # nosplit"):
        with boa.env.prank(u):
            pasanaku_contract.join_pasanaku(pending_idx)


def test_join_duplicate_reverts(pasanaku_contract, owner, usdc_contract, users):
    amount_raw = PASANAKU_AMOUNT_RAW
    create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users[:2],
        amount_raw,
    )
    pending_idx = 0
    with boa.reverts(dev="participant already joined # nosplit"):
        with boa.env.prank(users[0]):
            pasanaku_contract.join_pasanaku(pending_idx)


def test_join_emits_event(pasanaku_contract, owner, usdc_contract, users):
    amount_raw = PASANAKU_AMOUNT_RAW
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, users[:2], amount_raw
    )
    with boa.env.prank(users[0]):
        token_id = create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)
    with boa.env.prank(users[1]):
        pasanaku_contract.join_pasanaku(token_id)

    joined = [
        log
        for log in pasanaku_contract.get_logs()
        if type(log).__name__ == "PasanakuJoined"
    ]
    assert len(joined) == 1
    assert joined[0].token_id == token_id
    assert joined[0].account == users[1]
    assert joined[0].participant_count == 2


def test_full_join_starts_pasanaku(pasanaku_contract, owner, usdc_contract, users):
    amount_raw = PASANAKU_AMOUNT_RAW
    create_and_join_all(
        pasanaku_contract,
        usdc_contract,
        owner,
        users,
        amount_raw,
    )
    join_logs = pasanaku_contract.get_logs()
    started = [log for log in join_logs if type(log).__name__ == "PasanakuStarted"]
    assert len(started) == 1
    tid = started[0].token_id
    assert started[0].asset == usdc_contract.address
    assert started[0].amount == amount_raw

    st = pasanaku_contract.pasanaku(tid)
    assert st.started != 0
    assert st.ended == 0


def test_leave_pasanaku_before_stale_reverts(
    pasanaku_contract, owner, usdc_contract, users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, users[:2], amount_raw
    )
    with boa.env.prank(users[0]):
        token_id = create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)
    with boa.env.prank(users[1]):
        pasanaku_contract.join_pasanaku(token_id)

    with boa.reverts(dev="pasanaku is not stale"):
        with boa.env.prank(users[1]):
            pasanaku_contract.leave_pasanaku(token_id)


def test_leave_stale_pending_pasanaku_removes_participant_and_unlocks_collateral(
    pasanaku_contract, owner, usdc_contract, users
):
    amount_raw = PASANAKU_AMOUNT_RAW
    locked = pledge(amount_raw)
    users = users[:3]
    leaver = users[1]
    remaining = [users[0], users[2]]

    with boa.env.prank(owner):
        pasanaku_contract.set_stale_time(DAYS_3)
    fund_collateral_for_users(
        pasanaku_contract, usdc_contract, owner, users, amount_raw
    )
    with boa.env.prank(users[0]):
        token_id = create_pasanaku(pasanaku_contract, usdc_contract.address, amount_raw)
    for user in users[1:]:
        with boa.env.prank(user):
            pasanaku_contract.join_pasanaku(token_id)

    boa.env.time_travel(seconds=DAYS_3)
    with boa.env.prank(leaver):
        pasanaku_contract.leave_pasanaku(token_id)

    left = [
        log
        for log in pasanaku_contract.get_logs()
        if type(log).__name__ == "PasanakuLeft"
    ]
    assert any(log.account == leaver for log in left)

    st = pasanaku_contract.pasanaku(token_id)
    assert len(st.participants) == 2
    assert leaver not in st.participants
    assert set(st.participants) == set(remaining)
    assert pasanaku_contract.collateral_in_use(leaver, usdc_contract.address) == 0
    assert pasanaku_contract.free_collateral(leaver, usdc_contract.address) == locked
    for user in remaining:
        assert (
            pasanaku_contract.collateral_in_use(user, usdc_contract.address) == locked
        )


def test_leave_started_pasanaku_reverts(pasanaku_contract, started_pasanaku):
    tid = started_pasanaku["token_id"]
    leaver = started_pasanaku["users"][1]

    boa.env.time_travel(seconds=DAYS_40)
    with boa.reverts(dev="pasanaku not started"):
        with boa.env.prank(leaver):
            pasanaku_contract.leave_pasanaku(tid)
