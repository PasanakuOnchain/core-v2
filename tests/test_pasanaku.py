import boa
from hypothesis import HealthCheck, given, settings
from hypothesis.stateful import RuleBasedStateMachine, initialize, invariant, rule
import hypothesis.strategies as st
from src import pasanaku
from src._mocks import erc20_mock
from tests.helpers import mint_token

USERS_COUNT = 3
MAX_AMOUNT = 10**12


def test_protocol_fee(pasanaku_contract):
    assert pasanaku_contract.protocolFee() == int(0.000075 * 10**18)


def test_deposit_collateral(pasanaku_contract, alice, owner, usdc_contract):
    amount = mint_token(owner, usdc_contract, alice, 10_000)

    assert usdc_contract.balanceOf(alice) == amount

    with boa.env.prank(alice):
        usdc_contract.approve(pasanaku_contract.address, amount)
        pasanaku_contract.addCollateral(usdc_contract.address, amount)

    assert pasanaku_contract.collateralReserves(usdc_contract.address) == amount
    assert pasanaku_contract.freeCollateral(alice, usdc_contract.address) == amount
    assert pasanaku_contract.lockedCollateral(alice, 0) == 0


def test_deposit_collateral_and_withdraw(
    pasanaku_contract, alice, owner, usdc_contract
):
    amount = mint_token(owner, usdc_contract, alice, 10_000)
    assert usdc_contract.balanceOf(alice) == amount

    with boa.env.prank(alice):
        usdc_contract.approve(pasanaku_contract.address, amount)
        pasanaku_contract.addCollateral(usdc_contract.address, amount)

    assert usdc_contract.balanceOf(pasanaku_contract.address) == amount

    with boa.env.prank(alice):
        pasanaku_contract.removeCollateral(usdc_contract.address, amount)
        assert pasanaku_contract.collateralReserves(usdc_contract.address) == 0

    assert pasanaku_contract.collateralReserves(usdc_contract.address) == 0
    assert pasanaku_contract.freeCollateral(alice, usdc_contract.address) == 0
    assert usdc_contract.balanceOf(alice) == amount


def test_deposit_multiple_users(pasanaku_contract, tokens, users, owner):
    for token in tokens:
        collateral_reserves = 0
        for user in users:
            amount = mint_token(owner, token, user, 10_000)
            assert token.balanceOf(user) == amount

            with boa.env.prank(user):
                token.approve(pasanaku_contract.address, amount)
                pasanaku_contract.addCollateral(token.address, amount)
                collateral_reserves += amount

        assert (
            pasanaku_contract.collateralReserves(token.address) == collateral_reserves
        )
        assert pasanaku_contract.freeCollateral(user, token.address) == amount
        assert pasanaku_contract.lockedCollateral(user, 0) == 0


def test_deposit_multiple_users_and_withdraw(pasanaku_contract, tokens, users, owner):
    for token in tokens:
        for user in users:
            amount = mint_token(owner, token, user, 10_000)
            assert token.balanceOf(user) == amount

            with boa.env.prank(user):
                token.approve(pasanaku_contract.address, amount)
                pasanaku_contract.addCollateral(token.address, amount)

    for token in tokens:
        for user in users:
            amount = mint_token(owner, token, user, 10_000)
            with boa.env.prank(user):
                pasanaku_contract.removeCollateral(token.address, amount)

    assert pasanaku_contract.collateralReserves(token.address) == 0
    assert pasanaku_contract.freeCollateral(user, token.address) == 0
    assert pasanaku_contract.lockedCollateral(user, 0) == 0


def test_add_collateral_zero_amount_reverts(pasanaku_contract, alice, usdc_contract):
    with boa.reverts("pasanaku: invalid amount"):
        with boa.env.prank(alice):
            pasanaku_contract.addCollateral(usdc_contract.address, 0)


def test_add_collateral_unsupported_asset_reverts(pasanaku_contract, alice):
    fake = boa.env.generate_address()
    with boa.reverts("pasanaku: unsupported asset"):
        with boa.env.prank(alice):
            pasanaku_contract.addCollateral(fake, 100)


def test_remove_collateral_zero_amount_reverts(pasanaku_contract, alice, usdc_contract):
    with boa.reverts("pasanaku: invalid amount"):
        with boa.env.prank(alice):
            pasanaku_contract.removeCollateral(usdc_contract.address, 0)


def test_remove_collateral_unsupported_asset_reverts(pasanaku_contract, alice):
    fake = boa.env.generate_address()
    with boa.reverts("pasanaku: unsupported asset"):
        with boa.env.prank(alice):
            pasanaku_contract.removeCollateral(fake, 100)


def test_remove_collateral_exceeds_free_reverts(
    pasanaku_contract, alice, owner, usdc_contract
):
    amount = mint_token(owner, usdc_contract, alice, 100)
    with boa.env.prank(alice):
        usdc_contract.approve(pasanaku_contract.address, amount)
        pasanaku_contract.addCollateral(usdc_contract.address, amount)

    with boa.reverts("pasanaku: insufficient free collateral"):
        with boa.env.prank(alice):
            pasanaku_contract.removeCollateral(usdc_contract.address, amount + 1)


@given(amount=st.integers(min_value=1, max_value=10**12))
@settings(
    max_examples=100,
    deadline=None,
    suppress_health_check=[HealthCheck.function_scoped_fixture],
)
def test_fuzz_add_collateral_any_amount(
    pasanaku_contract, alice, owner, usdc_contract, amount
):
    with boa.env.anchor():
        with boa.env.prank(owner):
            usdc_contract.mint(alice, amount)
        with boa.env.prank(alice):
            usdc_contract.approve(pasanaku_contract.address, amount)
            pasanaku_contract.addCollateral(usdc_contract.address, amount)

        assert pasanaku_contract.freeCollateral(alice, usdc_contract.address) == amount
        assert pasanaku_contract.collateralReserves(usdc_contract.address) == amount
        assert usdc_contract.balanceOf(pasanaku_contract.address) == amount


@given(amount=st.integers(min_value=1, max_value=10**12))
@settings(
    max_examples=100,
    deadline=None,
    suppress_health_check=[HealthCheck.function_scoped_fixture],
)
def test_fuzz_add_and_remove_collateral_roundtrip(
    pasanaku_contract, alice, owner, usdc_contract, amount
):
    with boa.env.anchor():
        with boa.env.prank(owner):
            usdc_contract.mint(alice, amount)

        balance_before = usdc_contract.balanceOf(alice)

        with boa.env.prank(alice):
            usdc_contract.approve(pasanaku_contract.address, amount)
            pasanaku_contract.addCollateral(usdc_contract.address, amount)
            pasanaku_contract.removeCollateral(usdc_contract.address, amount)

        assert usdc_contract.balanceOf(alice) == balance_before
        assert pasanaku_contract.freeCollateral(alice, usdc_contract.address) == 0
        assert pasanaku_contract.collateralReserves(usdc_contract.address) == 0


@given(
    total=st.integers(min_value=2, max_value=10**12),
    fraction=st.floats(min_value=0.01, max_value=0.99),
)
@settings(
    max_examples=100,
    deadline=None,
    suppress_health_check=[HealthCheck.function_scoped_fixture],
)
def test_fuzz_partial_remove_collateral(
    pasanaku_contract, alice, owner, usdc_contract, total, fraction
):
    partial = max(1, int(total * fraction))
    if partial >= total:
        return

    with boa.env.anchor():
        with boa.env.prank(owner):
            usdc_contract.mint(alice, total)
        with boa.env.prank(alice):
            usdc_contract.approve(pasanaku_contract.address, total)
            pasanaku_contract.addCollateral(usdc_contract.address, total)
            pasanaku_contract.removeCollateral(usdc_contract.address, partial)

        remaining = total - partial
        assert (
            pasanaku_contract.freeCollateral(alice, usdc_contract.address) == remaining
        )
        assert pasanaku_contract.collateralReserves(usdc_contract.address) == remaining


@given(amount=st.integers(min_value=1, max_value=10**12))
@settings(
    max_examples=100,
    deadline=None,
    suppress_health_check=[HealthCheck.function_scoped_fixture],
)
def test_fuzz_create_lobby_any_amount(
    pasanaku_contract, owner, usdc_contract, protocol_fee, amount
):
    with boa.env.anchor():
        with boa.env.prank(owner):
            token_id = pasanaku_contract.create(
                usdc_contract.address, amount, value=protocol_fee
            )
        rs = pasanaku_contract.rotatingSavings(token_id)
        assert rs[2] == amount
        assert rs[7] is False


class CollateralStateMachine(RuleBasedStateMachine):
    def __init__(self):
        super().__init__()
        self.shadow = {}
        self.user_addrs = []
        self.token_contracts = []
        self.token_addrs = []
        self.contract = None
        self.deployer = None

    @initialize()
    def setup(self):
        self.deployer = boa.env.generate_address()
        boa.env.set_balance(self.deployer, 10**18)

        self.user_addrs = []
        for _ in range(USERS_COUNT):
            addr = boa.env.generate_address()
            boa.env.set_balance(addr, 10**18)
            self.user_addrs.append(addr)

        with boa.env.prank(self.deployer):
            t1 = erc20_mock.deploy("T1", "T1", 6, 0, "t1", "1")
            t2 = erc20_mock.deploy("T2", "T2", 6, 0, "t2", "1")
            t3 = erc20_mock.deploy("T3", "T3", 6, 0, "t3", "1")
            self.token_contracts = [t1, t2, t3]
            self.token_addrs = [t1.address, t2.address, t3.address]
            self.contract = pasanaku.deploy(self.token_addrs)

        self.shadow = {}
        for user in self.user_addrs:
            self.shadow[user] = {}
            for addr in self.token_addrs:
                self.shadow[user][addr] = 0

    @rule(
        user_idx=st.integers(min_value=0, max_value=USERS_COUNT - 1),
        token_idx=st.integers(min_value=0, max_value=2),
        amount=st.integers(min_value=1, max_value=MAX_AMOUNT),
    )
    def add_collateral(self, user_idx, token_idx, amount):
        user = self.user_addrs[user_idx]
        token = self.token_contracts[token_idx]

        with boa.env.prank(self.deployer):
            token.mint(user, amount)
        with boa.env.prank(user):
            token.approve(self.contract.address, amount)
            self.contract.addCollateral(token.address, amount)

        self.shadow[user][token.address] += amount

    @rule(
        user_idx=st.integers(min_value=0, max_value=USERS_COUNT - 1),
        token_idx=st.integers(min_value=0, max_value=2),
        fraction=st.floats(min_value=0.01, max_value=1.0),
    )
    def remove_collateral(self, user_idx, token_idx, fraction):
        user = self.user_addrs[user_idx]
        token = self.token_contracts[token_idx]
        balance = self.shadow[user][token.address]
        if balance == 0:
            return

        amount = max(1, int(balance * fraction))
        if amount > balance:
            amount = balance

        with boa.env.prank(user):
            self.contract.removeCollateral(token.address, amount)

        self.shadow[user][token.address] -= amount

    @invariant()
    def reserves_match_shadow_sum(self):
        for token_addr in self.token_addrs:
            expected = sum(self.shadow[u][token_addr] for u in self.user_addrs)
            assert self.contract.collateralReserves(token_addr) == expected

    @invariant()
    def free_collateral_matches_shadow(self):
        for user in self.user_addrs:
            for token_addr in self.token_addrs:
                assert (
                    self.contract.freeCollateral(user, token_addr)
                    == self.shadow[user][token_addr]
                )

    @invariant()
    def erc20_solvency(self):
        for i, token_addr in enumerate(self.token_addrs):
            token = self.token_contracts[i]
            assert token.balanceOf(
                self.contract.address
            ) >= self.contract.collateralReserves(token_addr)


TestCollateralInvariants = CollateralStateMachine.TestCase
