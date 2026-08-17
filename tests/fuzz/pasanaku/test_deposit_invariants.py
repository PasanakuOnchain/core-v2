import boa
from hypothesis import HealthCheck, settings
from hypothesis import strategies as st
from hypothesis.stateful import RuleBasedStateMachine, invariant, rule

from src import Pasanaku as pasanaku  # pyright: ignore[reportAttributeAccessIssue, reportUnknownVariableType]
from tests.mocks import erc20_mock, erc4626_mock  # pyright: ignore[reportAttributeAccessIssue, reportUnknownVariableType]

boa.env.enable_fast_mode()

_MAX_ASSETS = 1_000_000 * 10**6


class DepositStateMachine(RuleBasedStateMachine):
    def __init__(self) -> None:
        super().__init__()
        self._anchor = boa.env.anchor()
        self._anchor.__enter__()

        self.owner = boa.env.generate_address(alias="owner")
        self.actors = tuple(
            boa.env.generate_address(alias=f"actor-{index}") for index in range(3)
        )

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

        self.expected_free_shares = {actor: 0 for actor in self.actors}

    def teardown(self) -> None:
        self._anchor.__exit__(None, None, None)

    @rule(
        payer_index=st.integers(min_value=0, max_value=2),
        receiver_index=st.integers(min_value=0, max_value=2),
        requested_assets=st.integers(min_value=1, max_value=_MAX_ASSETS),
    )
    def deposit(
        self,
        payer_index: int,
        receiver_index: int,
        requested_assets: int,
    ) -> None:
        payer = self.actors[payer_index]
        receiver = self.actors[receiver_index]
        minimum_assets = self.vault.previewMint(1)
        assets = max(requested_assets, minimum_assets)

        # ================= Setup =================
        with boa.env.prank(self.owner):
            self.asset.mint(payer, assets)

        payer_assets_before = self.asset.balanceOf(payer)
        vault_assets_before = self.vault.totalAssets()
        vault_shares_before = self.vault.balanceOf(self.pasanaku.address)
        receiver_free_shares_before = self.pasanaku.free_shares(receiver)
        pasanaku_assets_before = self.asset.balanceOf(self.pasanaku.address)

        with boa.env.prank(payer):
            self.asset.approve(self.pasanaku.address, assets)

            # ================= Execute =================
            shares = self.pasanaku.deposit(assets, receiver)

        assert shares > 0
        assert self.asset.balanceOf(payer) == payer_assets_before - assets
        assert self.vault.totalAssets() == vault_assets_before + assets
        assert (
            self.vault.balanceOf(self.pasanaku.address) == vault_shares_before + shares
        )
        assert (
            self.pasanaku.free_shares(receiver) == receiver_free_shares_before + shares
        )
        assert self.asset.balanceOf(self.pasanaku.address) == pasanaku_assets_before

        # ================= Update the reference model =================
        self.expected_free_shares[receiver] += shares

    @rule(
        donated_assets=st.integers(min_value=1, max_value=_MAX_ASSETS),
    )
    def donate_yield(self, donated_assets: int) -> None:
        shares_before = self.vault.balanceOf(self.pasanaku.address)
        assets_before = self.vault.totalAssets()

        with boa.env.prank(self.owner):
            self.asset.mint(self.owner, donated_assets)
            self.asset.approve(self.vault.address, donated_assets)
            self.vault.donate(donated_assets)

        assert self.vault.totalAssets() == assets_before + donated_assets
        assert self.vault.balanceOf(self.pasanaku.address) == shares_before

    @invariant()
    def free_shares_match_reference_model(self) -> None:
        for actor, expected_shares in self.expected_free_shares.items():
            assert self.pasanaku.free_shares(actor) == expected_shares

    @invariant()
    def vault_shares_are_fully_accounted_for(self) -> None:
        accounted_shares = sum(
            self.pasanaku.free_shares(actor) for actor in self.actors
        )
        assert self.vault.balanceOf(self.pasanaku.address) == accounted_shares

    @invariant()
    def no_idle_underlying_in_pasanaku(self) -> None:
        assert self.asset.balanceOf(self.pasanaku.address) == 0


TestDepositStateMachine = DepositStateMachine.TestCase
TestDepositStateMachine.settings = settings(
    max_examples=25,
    stateful_step_count=20,
    deadline=None,
    suppress_health_check=[HealthCheck.too_slow],
)
