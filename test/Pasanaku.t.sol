// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Pasanaku} from "pasanaku/Pasanaku.sol";
import {IPasanaku} from "pasanaku/interfaces/IPasanaku.sol";
import {TokenDescriptor} from "pasanaku/metadata/TokenDescriptor.sol";
import {LayoutEnded} from "pasanaku/metadata/layouts/LayoutEnded.sol";
import {LayoutOngoing} from "pasanaku/metadata/layouts/LayoutOngoing.sol";
import {MockERC20} from "tests/_mocks/MockERC20.sol";
import {ReentrantMockERC20} from "tests/_mocks/ReentrantMockERC20.sol";

contract PasanakuTest is Test {
    event LobbyCreated(
        address indexed asset,
        uint256 amount,
        uint256 indexed tokenId,
        address indexed creator,
        uint256 createdAt,
        uint8 minParticipants,
        uint8 maxParticipants
    );

    event Deposited(
        address indexed participant, uint256 indexed tokenId, uint256 index, uint256 amount, uint256 totalDeposited
    );

    event Claimed(
        address indexed participant, uint256 indexed tokenId, uint256 index, uint256 amount, uint256 totalDeposited
    );

    event Ended(uint256 indexed tokenId, uint256 lastUpdatedAt);

    Pasanaku public pasanaku;
    TokenDescriptor public tokenDescriptor;
    LayoutEnded public layoutEnded;
    LayoutOngoing public layoutOngoing;
    MockERC20 public token;

    address public owner;
    address public p1;
    address public p2;
    address public p3;

    uint256 constant AMOUNT = 1e18;
    uint256 constant SUPPORTED_ASSETS_COUNT = 10;

    function setUp() public {
        owner = makeAddr("owner");
        p1 = makeAddr("p1");
        p2 = makeAddr("p2");
        p3 = makeAddr("p3");

        token = new MockERC20("Test Token", "TST", 18);
        token.mint(p1, 1000e18);
        token.mint(p2, 1000e18);
        token.mint(p3, 1000e18);

        address[SUPPORTED_ASSETS_COUNT] memory assets;
        assets[0] = address(token);
        for (uint256 i = 1; i < SUPPORTED_ASSETS_COUNT; i++) {
            assets[i] = address(0);
        }

        layoutEnded = new LayoutEnded();
        layoutOngoing = new LayoutOngoing();
        tokenDescriptor = new TokenDescriptor(address(layoutEnded), address(layoutOngoing));

        vm.prank(owner);
        pasanaku = new Pasanaku(assets, address(tokenDescriptor));
    }

    function _fundAndApprove(address account, uint256 amount) internal {
        vm.prank(account);
        token.approve(address(pasanaku), amount);
    }

    /// @dev Per-seat lock on join equals the round `amount` stored on the game (`rs.amount`).
    function _lockAmount() internal pure returns (uint256) {
        return AMOUNT;
    }

    function _addCollateralAndJoin(address user, uint256 tokenId) internal {
        vm.startPrank(user);
        token.approve(address(pasanaku), _lockAmount());
        pasanaku.addCollateral(address(token), _lockAmount());
        pasanaku.join(tokenId);
        vm.stopPrank();
    }

    function _openLobby(uint8 minP, uint8 maxP) internal returns (uint256 tid) {
        vm.prank(owner);
        tid = pasanaku.create(address(token), AMOUNT, minP, maxP);
    }

    function _startTwoPlayerGame() internal returns (uint256 tid) {
        tid = _openLobby(2, 2);
        _addCollateralAndJoin(p1, tid);
        _addCollateralAndJoin(p2, tid);
        vm.prank(owner);
        pasanaku.finalizeLobby(tid);
    }

    function _startThreePlayerGame() internal returns (uint256 tid) {
        tid = _openLobby(2, 3);
        _addCollateralAndJoin(p1, tid);
        _addCollateralAndJoin(p2, tid);
        _addCollateralAndJoin(p3, tid);
        vm.prank(owner);
        pasanaku.finalizeLobby(tid);
    }

    function test_constructor_setsOwnerAndSupportedAssets() public view {
        assertEq(pasanaku.owner(), owner);
        assertEq(pasanaku.tokenDescriptor(), address(tokenDescriptor));
        address[SUPPORTED_ASSETS_COUNT] memory assets = pasanaku.supportedAssets();
        assertEq(assets[0], address(token));
    }

    function test_protocolFee_returnsZero() public view {
        assertEq(pasanaku.protocolFee(), 0);
    }

    function test_nextTokenId_startsAtZero() public view {
        assertEq(pasanaku.nextTokenId(), 0);
    }

    function test_create_success() public {
        vm.expectEmit(true, true, true, true);
        emit LobbyCreated(address(token), AMOUNT, 0, owner, block.timestamp, 2, 12);

        vm.prank(owner);
        uint256 tid = pasanaku.create(address(token), AMOUNT, 2, 12);

        assertEq(tid, 0);
        IPasanaku.RotatingSavings memory rs = pasanaku.rotatingSavings(0);
        assertEq(rs.asset, address(token));
        assertEq(rs.amount, AMOUNT);
        assertEq(rs.currentIndex, 0);
        assertEq(rs.totalDeposited, 0);
        assertEq(rs.tokenId, 0);
        assertFalse(rs.ended);
        assertFalse(rs.started);
        assertFalse(rs.cancelled);
        assertEq(rs.creator, owner);
        assertEq(uint256(rs.minParticipants), 2);
        assertEq(uint256(rs.maxParticipants), 12);
        assertEq(rs.participants.length, 0);
    }

    function test_create_incrementsTokenId() public {
        vm.startPrank(owner);
        pasanaku.create(address(token), AMOUNT, 2, 12);
        assertEq(pasanaku.nextTokenId(), 1);
        pasanaku.create(address(token), AMOUNT, 2, 12);
        assertEq(pasanaku.nextTokenId(), 2);
        vm.stopPrank();
    }

    function test_create_revertsUnsupportedAsset() public {
        address unsupportedToken = address(new MockERC20("Other", "OTH", 18));

        vm.prank(owner);
        vm.expectRevert(Pasanaku.Pasanaku__UnsupportedAsset.selector);
        pasanaku.create(unsupportedToken, AMOUNT, 2, 12);
    }

    function test_create_revertsInvalidLobby() public {
        vm.prank(owner);
        vm.expectRevert(Pasanaku.Pasanaku__NotEnoughParticipants.selector);
        pasanaku.create(address(token), AMOUNT, 1, 12);

        vm.prank(owner);
        vm.expectRevert(Pasanaku.Pasanaku__InvalidLobbyParams.selector);
        pasanaku.create(address(token), AMOUNT, 5, 3);
    }

    function test_create_revertsTooManyMax() public {
        vm.prank(owner);
        vm.expectRevert(Pasanaku.Pasanaku__TooManyParticipants.selector);
        pasanaku.create(address(token), AMOUNT, 2, 13);
    }

    function test_join_and_finalize() public {
        uint256 tid = _openLobby(2, 2);
        _addCollateralAndJoin(p1, tid);
        _addCollateralAndJoin(p2, tid);

        assertEq(pasanaku.lockedCollateralOf(p1, tid), _lockAmount());
        assertEq(pasanaku.freeCollateralOf(p1, address(token)), 0);

        vm.prank(owner);
        pasanaku.finalizeLobby(tid);

        IPasanaku.RotatingSavings memory rs = pasanaku.rotatingSavings(tid);
        assertTrue(rs.started);
        assertEq(rs.participants.length, 2);
        assertTrue(
            (rs.participants[0] == p1 || rs.participants[0] == p2)
                && (rs.participants[1] == p1 || rs.participants[1] == p2) && rs.participants[0] != rs.participants[1]
        );
    }

    function test_join_revertsLotFull() public {
        uint256 tid = _openLobby(2, 2);
        _addCollateralAndJoin(p1, tid);
        _addCollateralAndJoin(p2, tid);
        token.mint(p3, 100e18);
        vm.startPrank(p3);
        token.approve(address(pasanaku), _lockAmount());
        pasanaku.addCollateral(address(token), _lockAmount());
        vm.expectRevert(Pasanaku.Pasanaku__LotFull.selector);
        pasanaku.join(tid);
        vm.stopPrank();
    }

    function test_finalize_revertsUntilLobbyFull() public {
        uint256 tid = _openLobby(2, 3);
        _addCollateralAndJoin(p1, tid);
        _addCollateralAndJoin(p2, tid);
        vm.prank(owner);
        vm.expectRevert(Pasanaku.Pasanaku__CannotFinalize.selector);
        pasanaku.finalizeLobby(tid);

        _addCollateralAndJoin(p3, tid);
        vm.prank(owner);
        pasanaku.finalizeLobby(tid);
        assertTrue(pasanaku.rotatingSavings(tid).started);
    }

    function test_leaveLobby_beforeFinalize() public {
        uint256 tid = _openLobby(2, 12);
        _addCollateralAndJoin(p1, tid);
        assertEq(pasanaku.balanceOf(p1, tid), 1);

        vm.prank(p1);
        pasanaku.leaveLobby(tid);

        assertEq(pasanaku.balanceOf(p1, tid), 0);
        assertEq(pasanaku.freeCollateralOf(p1, address(token)), _lockAmount());
        assertEq(pasanaku.rotatingSavings(tid).participants.length, 0);
    }

    function test_cancelLobby_refundsLocks() public {
        uint256 tid = _openLobby(2, 12);
        _addCollateralAndJoin(p1, tid);
        _addCollateralAndJoin(p2, tid);

        vm.prank(owner);
        pasanaku.cancelLobby(tid);

        assertTrue(pasanaku.rotatingSavings(tid).cancelled);
        assertEq(pasanaku.freeCollateralOf(p1, address(token)), _lockAmount());
        assertEq(pasanaku.freeCollateralOf(p2, address(token)), _lockAmount());
    }

    function test_deposit_success() public {
        uint256 tid = _startTwoPlayerGame();
        address ben = pasanaku.beneficiary(tid);
        address payer = ben == p1 ? p2 : p1;

        _fundAndApprove(payer, AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit Deposited(payer, tid, 0, AMOUNT, AMOUNT);

        vm.prank(payer);
        pasanaku.deposit(tid);

        assertEq(pasanaku.totalDeposited(tid), AMOUNT);
        assertTrue(pasanaku.hasDeposited(payer, tid));
    }

    function test_deposit_revertsWhenLobbyNotStarted() public {
        uint256 tid = _openLobby(2, 12);
        _addCollateralAndJoin(p1, tid);
        _fundAndApprove(p1, AMOUNT);
        vm.prank(p1);
        vm.expectRevert(Pasanaku.Pasanaku__CannotDeposit.selector);
        pasanaku.deposit(tid);
    }

    function test_claim_success() public {
        uint256 tid = _startTwoPlayerGame();
        address ben = pasanaku.beneficiary(tid);
        address payer = ben == p1 ? p2 : p1;

        _fundAndApprove(payer, AMOUNT);
        vm.prank(payer);
        pasanaku.deposit(tid);

        uint256 balanceBefore = token.balanceOf(ben);

        vm.expectEmit(true, true, false, true);
        emit Claimed(ben, tid, 0, AMOUNT, 0);

        vm.prank(ben);
        pasanaku.claim(tid);

        assertEq(token.balanceOf(ben), balanceBefore + AMOUNT);
        assertEq(pasanaku.totalDeposited(tid), 0);
        assertEq(pasanaku.rotatingSavings(tid).currentIndex, 1);
    }

    function test_claim_lastParticipant_setsEnded_releasesCollateral() public {
        uint256 tid = _startTwoPlayerGame();
        address ben0 = pasanaku.beneficiary(tid);
        address payer0 = ben0 == p1 ? p2 : p1;

        _fundAndApprove(payer0, AMOUNT);
        vm.prank(payer0);
        pasanaku.deposit(tid);

        vm.prank(ben0);
        pasanaku.claim(tid);

        address ben1 = pasanaku.beneficiary(tid);
        address payer1 = ben1 == p1 ? p2 : p1;

        _fundAndApprove(payer1, AMOUNT);
        vm.prank(payer1);
        pasanaku.deposit(tid);

        vm.expectEmit(true, false, false, false);
        emit Ended(tid, block.timestamp);

        vm.prank(ben1);
        pasanaku.claim(tid);

        assertTrue(pasanaku.rotatingSavings(tid).ended);
        assertEq(pasanaku.beneficiary(tid), address(0));
        assertEq(pasanaku.lockedCollateralOf(p1, tid), 0);
        assertEq(pasanaku.lockedCollateralOf(p2, tid), 0);
        assertEq(pasanaku.freeCollateralOf(p1, address(token)), _lockAmount());
        assertEq(pasanaku.freeCollateralOf(p2, address(token)), _lockAmount());
    }

    function test_claim_threeParticipants_firstRound() public {
        uint256 tid = _startThreePlayerGame();
        address ben = pasanaku.beneficiary(tid);
        address payerA;
        address payerB;
        if (ben == p1) {
            payerA = p2;
            payerB = p3;
        } else if (ben == p2) {
            payerA = p1;
            payerB = p3;
        } else {
            payerA = p1;
            payerB = p2;
        }

        _fundAndApprove(payerA, AMOUNT);
        _fundAndApprove(payerB, AMOUNT);
        vm.prank(payerA);
        pasanaku.deposit(tid);
        vm.prank(payerB);
        pasanaku.deposit(tid);

        vm.prank(ben);
        pasanaku.claim(tid);

        assertEq(pasanaku.rotatingSavings(tid).currentIndex, 1);
        assertEq(pasanaku.totalDeposited(tid), 0);
    }

    function test_permissionlessClaim_afterGrace() public {
        uint256 tid = _startTwoPlayerGame();
        address ben = pasanaku.beneficiary(tid);
        address payer = ben == p1 ? p2 : p1;

        _fundAndApprove(payer, AMOUNT);
        vm.prank(payer);
        pasanaku.deposit(tid);

        vm.warp(block.timestamp + 31 days);

        address keeper = makeAddr("keeper");
        vm.prank(keeper);
        pasanaku.claim(tid);

        assertEq(pasanaku.rotatingSavings(tid).currentIndex, 1);
    }

    function test_removeCollateral_afterGameEnds() public {
        uint256 tid = _startTwoPlayerGame();
        address ben0 = pasanaku.beneficiary(tid);
        address payer0 = ben0 == p1 ? p2 : p1;
        _fundAndApprove(payer0, AMOUNT);
        vm.prank(payer0);
        pasanaku.deposit(tid);
        vm.prank(ben0);
        pasanaku.claim(tid);
        address ben1 = pasanaku.beneficiary(tid);
        address payer1 = ben1 == p1 ? p2 : p1;
        _fundAndApprove(payer1, AMOUNT);
        vm.prank(payer1);
        pasanaku.deposit(tid);
        vm.prank(ben1);
        pasanaku.claim(tid);

        uint256 beforeP1 = token.balanceOf(p1);
        vm.prank(p1);
        pasanaku.removeCollateral(address(token), _lockAmount());
        assertEq(token.balanceOf(p1), beforeP1 + _lockAmount());
    }

    function test_collectProtocolFees_success() public {
        vm.deal(address(pasanaku), 1 ether);

        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        pasanaku.collectProtocolFees();

        assertEq(owner.balance, ownerBalanceBefore + 1 ether);
        assertEq(address(pasanaku).balance, 0);
    }

    function test_collectProtocolFees_revertsWhenNotOwner() public {
        vm.deal(address(pasanaku), 1 ether);

        vm.prank(p1);
        vm.expectRevert();
        pasanaku.collectProtocolFees();
    }

    function test_threeParticipants_stallsAfterFirstRound() public {
        uint256 tid = _startThreePlayerGame();
        address ben0 = pasanaku.beneficiary(tid);
        address payerA;
        address payerB;
        if (ben0 == p1) {
            payerA = p2;
            payerB = p3;
        } else if (ben0 == p2) {
            payerA = p1;
            payerB = p3;
        } else {
            payerA = p1;
            payerB = p2;
        }

        _fundAndApprove(payerA, AMOUNT);
        _fundAndApprove(payerB, AMOUNT);
        vm.prank(payerA);
        pasanaku.deposit(tid);
        vm.prank(payerB);
        pasanaku.deposit(tid);

        vm.prank(ben0);
        pasanaku.claim(tid);

        address ben1 = pasanaku.beneficiary(tid);

        address alreadyDeposited;
        address canPay;
        address[3] memory all = [p1, p2, p3];
        for (uint256 i; i < 3; i++) {
            address a = all[i];
            if (a == ben1) continue;
            if (pasanaku.hasDeposited(a, tid)) {
                alreadyDeposited = a;
            } else {
                canPay = a;
            }
        }

        _fundAndApprove(alreadyDeposited, AMOUNT);
        vm.prank(alreadyDeposited);
        vm.expectRevert(Pasanaku.Pasanaku__CannotDeposit.selector);
        pasanaku.deposit(tid);

        _fundAndApprove(canPay, AMOUNT);
        vm.prank(canPay);
        pasanaku.deposit(tid);

        assertEq(pasanaku.totalDeposited(tid), AMOUNT);
        assertFalse(pasanaku.canClaim(ben1, tid));
    }

    function test_uri_matchesTokenDescriptor() public {
        uint256 tid = _startTwoPlayerGame();
        IPasanaku.RotatingSavings memory rs = pasanaku.rotatingSavings(tid);
        assertEq(pasanaku.uri(tid), tokenDescriptor.tokenURI(rs));
    }

    function test_uri_returnsJsonDataUriPrefix() public {
        uint256 tid = _startTwoPlayerGame();
        string memory u = pasanaku.uri(tid);
        assertTrue(LibString.startsWith(u, "data:application/json;base64,"));
    }

    function test_nonExistentTokenId_returnsEmptyState() public view {
        IPasanaku.RotatingSavings memory rs = pasanaku.rotatingSavings(999);
        assertEq(rs.creator, address(0));
    }

    function test_deposit_revertsOnReentrantToken() public {
        ReentrantMockERC20 reToken = new ReentrantMockERC20("Reentrant", "RNT", 18);
        reToken.mint(p1, 1000e18);
        reToken.mint(p2, 1000e18);

        address[SUPPORTED_ASSETS_COUNT] memory assets;
        assets[0] = address(reToken);
        for (uint256 i = 1; i < SUPPORTED_ASSETS_COUNT; i++) {
            assets[i] = address(0);
        }

        vm.prank(owner);
        Pasanaku p = new Pasanaku(assets, address(tokenDescriptor));

        vm.prank(owner);
        p.create(address(reToken), AMOUNT, 2, 2);

        vm.startPrank(p1);
        reToken.approve(address(p), AMOUNT);
        p.addCollateral(address(reToken), AMOUNT);
        p.join(0);
        vm.stopPrank();
        vm.startPrank(p2);
        reToken.approve(address(p), AMOUNT);
        p.addCollateral(address(reToken), AMOUNT);
        p.join(0);
        vm.stopPrank();
        vm.prevrandao(2);
        vm.prank(owner);
        p.finalizeLobby(0);

        reToken.setReenterDeposit(p, 0, p2);

        vm.prank(p2);
        reToken.approve(address(p), AMOUNT);

        vm.prank(p2);
        vm.expectRevert();
        p.deposit(0);
    }
}
