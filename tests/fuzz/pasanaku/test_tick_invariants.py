import boa
from hypothesis import HealthCheck, settings, strategies as st
from hypothesis.stateful import RuleBasedStateMachine, invariant, rule

from src import Pasanaku as pasanaku  # type: ignore  # pyright: ignore[reportAttributeAccessIssue, reportUnknownVariableType]
from tests.mocks import erc20_mock, erc4626_mock  # type: ignore  # pyright: ignore[reportAttributeAccessIssue, reportUnknownVariableType]
from tests.utils.constants import _MIN_TIME_INTERVAL, PASANAKU_AMOUNT_RAW
from tests.utils.helpers import create_and_join_all, generate_users, penalty_per_amount

boa.env.enable_fast_mode()

_TICK_PARTICIPANT_COUNT = 3
_HYPOTHESIS_SETTINGS = settings(
    max_examples=25,
    stateful_step_count=12,
    deadline=None,
    suppress_health_check=[HealthCheck.too_slow],
)


class StartedPoolHarness(RuleBasedStateMachine):
    def __init__(self) -> None:
        super().__init__()
        self._anchor = boa.env.anchor()
        self._anchor.__enter__()

        self.owner = boa.env.generate_address(alias="owner")
        self.participants = generate_users(_TICK_PARTICIPANT_COUNT)
        self.round_assets = PASANAKU_AMOUNT_RAW
        self.participant_count = _TICK_PARTICIPANT_COUNT
        self.claimed_rounds: set[int] = set()

        with boa.env.prank(self.owner):
            self.asset = erc20_mock.deploy(
                "USD Coin",
                "USDC",
                6,
                10_000,
                "fake-usdc",
                "1",
            )
            self.vault = erc4626_mock.deploy(self.asset.address)
            self.pasanaku = pasanaku.deploy(
                self.asset.address,
                self.vault.address,
                0,
                0,
            )

        self.token_id = create_and_join_all(
            self.pasanaku,
            self.asset,
            self.owner,
            self.participants,
            self.round_assets,
            self.participant_count,
        )
        self.roster = tuple(self.pasanaku.pasanaku(self.token_id).participants)

    def teardown(self) -> None:
        self._anchor.__exit__(None, None, None)

    def _pool(self):
        return self.pasanaku.pasanaku(self.token_id)

    def _collected_fee_shares(self) -> int:
        return self.pasanaku.eval("self._collected_fee_shares")

    def _accounted_shares(self) -> int:
        free = sum(self.pasanaku.free_shares(actor) for actor in self.roster)
        locked = sum(
            self.pasanaku.locked_shares(self.token_id, actor) for actor in self.roster
        )
        reserve = self.pasanaku.pool_reserve_shares(self.token_id)
        return free + locked + reserve + self._collected_fee_shares()

    def _pending_payout_sum(self) -> int:
        return sum(
            self.pasanaku.pending_payout(self.token_id, round_idx)
            for round_idx in range(self.participant_count)
        )


class TickAccountingInvariants(StartedPoolHarness):
    @invariant()
    def vault_shares_are_fully_accounted_for(self) -> None:
        assert self.vault.balanceOf(self.pasanaku.address) == self._accounted_shares()

    @invariant()
    def liquid_assets_match_escrow_and_payouts(self) -> None:
        assert self.asset.balanceOf(self.pasanaku.address) == (
            self.pasanaku.pool_escrow(self.token_id) + self._pending_payout_sum()
        )

    @invariant()
    def successful_deposits_match_round_flags(self) -> None:
        for actor in self.roster:
            flags = sum(
                int(
                    self.pasanaku.deposited_for_pasanaku(
                        self.token_id, round_idx, actor
                    )
                )
                for round_idx in range(self.participant_count)
            )
            assert (
                self.pasanaku.successful_obligated_deposits(self.token_id, actor)
                == flags
            )

    @invariant()
    def round_recipient_never_deposits(self) -> None:
        for round_idx, recipient in enumerate(self.roster):
            assert not self.pasanaku.deposited_for_pasanaku(
                self.token_id, round_idx, recipient
            )

    @invariant()
    def lifecycle_is_consistent(self) -> None:
        pool = self._pool()
        assert 0 <= pool.index <= self.participant_count
        if pool.ended == 0:
            assert pool.started != 0
            assert pool.index < self.participant_count
            assert self.pasanaku.active_pasanaku_count() == 1
        else:
            assert pool.index == self.participant_count
            assert self.pasanaku.active_pasanaku_count() == 0

    @invariant()
    def ended_pool_clears_collateral_buckets(self) -> None:
        pool = self._pool()
        if pool.ended == 0:
            return
        assert self.pasanaku.pool_reserve_shares(self.token_id) == 0
        assert self.pasanaku.pool_escrow(self.token_id) == 0
        for actor in self.roster:
            assert self.pasanaku.locked_shares(self.token_id, actor) == 0
            assert self.pasanaku.locked_asset_basis(self.token_id, actor) == 0
        free = sum(self.pasanaku.free_shares(actor) for actor in self.roster)
        assert self.vault.balanceOf(self.pasanaku.address) == (
            free + self._collected_fee_shares()
        )


class TickSettlementStateMachine(TickAccountingInvariants):
    @rule(
        funding_bits=st.integers(
            min_value=0,
            max_value=(1 << (_TICK_PARTICIPANT_COUNT - 1)) - 1,
        ),
    )
    def settle_next_round(self, funding_bits: int) -> None:
        pool = self._pool()
        if pool.ended != 0:
            return

        round_idx = pool.index
        recipient = pool.participants[round_idx]
        funded, missed = self._split_obligors(
            pool.participants, recipient, funding_bits
        )
        snapshot = self._capture_round_snapshot(
            pool.participants, recipient, funded, missed, round_idx
        )

        self._fund_obligors(funded)
        boa.env.time_travel(seconds=_MIN_TIME_INTERVAL)
        self.pasanaku.tick(self.token_id)

        self._assert_tick_settled(snapshot, funded, missed, recipient)
        if round_idx == self.participant_count - 1:
            self._assert_final_round_cleanup(pool.participants)
            return
        self._assert_nonfinal_miss_accounting(snapshot, funded, missed, recipient)

    def _split_obligors(self, participants, recipient, funding_bits: int):
        obligors = [actor for actor in participants if actor != recipient]
        funded = [
            obligor for bit, obligor in enumerate(obligors) if funding_bits & (1 << bit)
        ]
        missed = [obligor for obligor in obligors if obligor not in funded]
        return funded, missed

    def _capture_round_snapshot(
        self, participants, recipient, funded, missed, round_idx: int
    ) -> dict:
        return {
            "index": round_idx,
            "pending": self.pasanaku.pending_payout(self.token_id, round_idx),
            "success": {
                actor: self.pasanaku.successful_obligated_deposits(self.token_id, actor)
                for actor in participants
            },
            "missed_locked": {
                actor: self.pasanaku.locked_shares(self.token_id, actor)
                for actor in missed
            },
            "missed_basis": {
                actor: self.pasanaku.locked_asset_basis(self.token_id, actor)
                for actor in missed
            },
            "untouched_locked": {
                actor: self.pasanaku.locked_shares(self.token_id, actor)
                for actor in funded + [recipient]
            },
            "reserve": self.pasanaku.pool_reserve_shares(self.token_id),
        }

    def _fund_obligors(self, funded) -> None:
        for obligor in funded:
            with boa.env.prank(self.owner):
                self.asset.mint(obligor, self.round_assets)
            with boa.env.prank(obligor):
                self.asset.approve(self.pasanaku.address, self.round_assets)
                self.pasanaku.deposit_to_pasanaku(
                    self.round_assets, self.token_id, obligor
                )

    def _assert_tick_settled(self, snapshot, funded, missed, recipient) -> None:
        round_idx = snapshot["index"]
        assert self._pool().index == round_idx + 1
        assert self.pasanaku.pool_escrow(self.token_id) == 0
        assert self.pasanaku.pending_payout(self.token_id, round_idx) == (
            snapshot["pending"] + self.round_assets * (self.participant_count - 1)
        )

        for actor in funded:
            assert (
                self.pasanaku.successful_obligated_deposits(self.token_id, actor)
                == snapshot["success"][actor] + 1
            )
            assert self.pasanaku.deposited_for_pasanaku(self.token_id, round_idx, actor)
        for actor in missed:
            assert (
                self.pasanaku.successful_obligated_deposits(self.token_id, actor)
                == snapshot["success"][actor]
            )
            assert not self.pasanaku.deposited_for_pasanaku(
                self.token_id, round_idx, actor
            )
        assert (
            self.pasanaku.successful_obligated_deposits(self.token_id, recipient)
            == snapshot["success"][recipient]
        )
        assert not self.pasanaku.deposited_for_pasanaku(
            self.token_id, round_idx, recipient
        )

    def _assert_final_round_cleanup(self, participants) -> None:
        assert self._pool().ended != 0
        assert self.pasanaku.active_pasanaku_count() == 0
        assert self.pasanaku.pool_reserve_shares(self.token_id) == 0
        for actor in participants:
            assert self.pasanaku.locked_shares(self.token_id, actor) == 0
            assert self.pasanaku.locked_asset_basis(self.token_id, actor) == 0

    def _assert_nonfinal_miss_accounting(
        self, snapshot, funded, missed, recipient
    ) -> None:
        assert self._pool().ended == 0
        assert self.pasanaku.active_pasanaku_count() == 1
        for actor in funded + [recipient]:
            assert (
                self.pasanaku.locked_shares(self.token_id, actor)
                == snapshot["untouched_locked"][actor]
            )
        if missed:
            assert (
                self.pasanaku.pool_reserve_shares(self.token_id) > snapshot["reserve"]
            )
        else:
            assert (
                self.pasanaku.pool_reserve_shares(self.token_id) == snapshot["reserve"]
            )

        penalty = penalty_per_amount(self.round_assets)
        burned_shares = self.vault.previewWithdraw(self.round_assets)
        penalty_shares = self.vault.previewWithdraw(penalty)
        for actor in missed:
            assert self.pasanaku.locked_shares(self.token_id, actor) == (
                snapshot["missed_locked"][actor] - burned_shares - penalty_shares
            )
            assert self.pasanaku.locked_asset_basis(self.token_id, actor) == (
                snapshot["missed_basis"][actor] - self.round_assets - penalty
            )


class TickClaimStateMachine(TickSettlementStateMachine):
    @rule(round_idx=st.integers(min_value=0, max_value=_TICK_PARTICIPANT_COUNT - 1))
    def claim_round_payout(self, round_idx: int) -> None:
        amount = self.pasanaku.pending_payout(self.token_id, round_idx)
        if amount == 0 or round_idx in self.claimed_rounds:
            return

        recipient = self._pool().participants[round_idx]
        recipient_assets_before = self.asset.balanceOf(recipient)

        with boa.env.prank(recipient):
            self.pasanaku.claim_round_payout(self.token_id, round_idx)

        assert self.pasanaku.pending_payout(self.token_id, round_idx) == 0
        assert self.asset.balanceOf(recipient) == recipient_assets_before + amount
        self.claimed_rounds.add(round_idx)


TestTickSettlementStateMachine = TickSettlementStateMachine.TestCase
TestTickSettlementStateMachine.settings = _HYPOTHESIS_SETTINGS

TestTickClaimStateMachine = TickClaimStateMachine.TestCase
TestTickClaimStateMachine.settings = _HYPOTHESIS_SETTINGS
