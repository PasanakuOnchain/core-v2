// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Pasanaku} from "pasanaku/Pasanaku.sol";
import {IPasanaku} from "pasanaku/interfaces/IPasanaku.sol";
import {TokenDescriptor} from "pasanaku/metadata/TokenDescriptor.sol";
import {LayoutEnded} from "pasanaku/metadata/layouts/LayoutEnded.sol";
import {LayoutOngoing} from "pasanaku/metadata/layouts/LayoutOngoing.sol";
import {MockERC20} from "tests/_mocks/MockERC20.sol";
import {ReentrantMockERC20} from "tests/_mocks/ReentrantMockERC20.sol";

contract PasanakuTest is Test {
    event RotatingSavingsCreated(
        address[] participants,
        address indexed asset,
        uint256 amount,
        uint256 indexed tokenId,
        address indexed creator,
        uint256 createdAt
    );

    event Deposited(
        address indexed participant, uint256 indexed tokenId, uint256 index, uint256 amount, uint256 totalDeposited
    );

    event Claimed(
        address indexed participant, uint256 indexed tokenId, uint256 index, uint256 amount, uint256 totalDeposited
    );

    event Ended(uint256 indexed tokenId, uint256 lastUpdatedAt);

    event Recovered(address indexed participant, uint256 indexed tokenId, uint256 index, uint256 amount);

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

    function _createParticipants(uint256 n) internal returns (address[] memory) {
        address[] memory participants = new address[](n);
        for (uint256 i; i < n; i++) {
            participants[i] = makeAddr(string(abi.encodePacked("participant", i)));
            token.mint(participants[i], 1000e18);
        }
        return participants;
    }

    function _fundAndApprove(address account, uint256 amount) internal {
        vm.prank(account);
        token.approve(address(pasanaku), amount);
    }

    function _createRs(address creator_, address[] memory participants_) internal returns (uint256 tokenId) {
        vm.prank(creator_);
        pasanaku.create(address(token), participants_, AMOUNT);
        return 0;
    }

    function test_constructor_setsOwnerAndSupportedAssets() public view {
        assertEq(pasanaku.owner(), owner);
        assertEq(pasanaku.tokenDescriptor(), address(tokenDescriptor));
        address[SUPPORTED_ASSETS_COUNT] memory assets = pasanaku.supportedAssets();
        assertEq(assets[0], address(token));
    }

    function test_supportedAssets_returnsCorrectLength() public view {
        address[SUPPORTED_ASSETS_COUNT] memory assets = pasanaku.supportedAssets();
        assertEq(assets.length, 10);
    }

    function test_protocolFee_returnsZero() public view {
        assertEq(pasanaku.protocolFee(), 0);
    }

    function test_nextTokenId_startsAtZero() public view {
        assertEq(pasanaku.nextTokenId(), 0);
    }

    function test_create_success() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.expectEmit(true, true, true, true);
        emit RotatingSavingsCreated(participants, address(token), AMOUNT, 0, owner, block.timestamp);

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        IPasanaku.RotatingSavings memory rs = pasanaku.rotatingSavings(0);
        assertEq(rs.asset, address(token));
        assertEq(rs.amount, AMOUNT);
        assertEq(rs.currentIndex, 0);
        assertEq(rs.totalDeposited, 0);
        assertEq(rs.tokenId, 0);
        assertFalse(rs.ended);
        assertFalse(rs.recovered);
        assertEq(rs.creator, owner);

        assertEq(pasanaku.balanceOf(p1, 0), 1);
        assertEq(pasanaku.balanceOf(p2, 0), 1);
    }

    function test_create_incrementsTokenId() public {
        address[] memory participants = new address[](1);
        participants[0] = p1;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);
        assertEq(pasanaku.nextTokenId(), 1);

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);
        assertEq(pasanaku.nextTokenId(), 2);

        assertEq(pasanaku.rotatingSavings(0).tokenId, 0);
        assertEq(pasanaku.rotatingSavings(1).tokenId, 1);
    }

    function test_create_creatorCanBeParticipant() public {
        address[] memory participants = new address[](2);
        participants[0] = owner;
        participants[1] = p2;

        token.mint(owner, 1000e18);

        vm.prank(owner);
        bool success = pasanaku.create(address(token), participants, AMOUNT);
        assertTrue(success);
        assertEq(pasanaku.balanceOf(owner, 0), 1);
    }

    function test_create_revertsDuplicateParticipants() public {
        address[] memory participants = new address[](3);
        participants[0] = p1;
        participants[1] = p2;
        participants[2] = p1;

        vm.prank(owner);
        vm.expectRevert(Pasanaku.Pasanaku__DuplicateParticipant.selector);
        pasanaku.create(address(token), participants, AMOUNT);
    }

    function test_create_revertsUnsupportedAsset() public {
        address[] memory participants = new address[](1);
        participants[0] = p1;

        address unsupportedToken = address(new MockERC20("Other", "OTH", 18));

        vm.prank(owner);
        vm.expectRevert(Pasanaku.Pasanaku__UnsupportedAsset.selector);
        pasanaku.create(unsupportedToken, participants, AMOUNT);
    }

    function test_create_revertsInsufficientFee() public {
        vm.skip(pasanaku.protocolFee() == 0); // Cannot trigger when fee is 0
        address[] memory participants = new address[](1);
        participants[0] = p1;

        vm.prank(owner);
        vm.expectRevert(Pasanaku.Pasanaku__InsufficientFee.selector);
        pasanaku.create{value: 0}(address(token), participants, AMOUNT);
    }

    function test_create_revertsNoParticipants() public {
        address[] memory participants;

        vm.prank(owner);
        vm.expectRevert(Pasanaku.Pasanaku__NoParticipants.selector);
        pasanaku.create(address(token), participants, AMOUNT);
    }

    function test_create_revertsTooManyParticipants() public {
        address[] memory participants = _createParticipants(13);

        vm.prank(owner);
        vm.expectRevert(Pasanaku.Pasanaku__TooManyParticipants.selector);
        pasanaku.create(address(token), participants, AMOUNT);
    }

    function test_deposit_success() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        vm.prank(p2);
        token.approve(address(pasanaku), AMOUNT);

        uint256 balanceBefore = token.balanceOf(address(pasanaku));

        vm.expectEmit(true, true, false, true);
        emit Deposited(p2, 0, 0, AMOUNT, AMOUNT);

        vm.prank(p2);
        pasanaku.deposit(0);

        assertEq(pasanaku.totalDeposited(0), AMOUNT);
        assertTrue(pasanaku.hasDeposited(p2, 0));
        assertEq(token.balanceOf(address(pasanaku)), balanceBefore + AMOUNT);
    }

    function test_deposit_multipleParticipants() public {
        address[] memory participants = new address[](3);
        participants[0] = p1;
        participants[1] = p2;
        participants[2] = p3;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        _fundAndApprove(p3, AMOUNT);

        vm.prank(p2);
        pasanaku.deposit(0);

        vm.prank(p3);
        pasanaku.deposit(0);

        assertEq(pasanaku.totalDeposited(0), 2 * AMOUNT);
    }

    function test_deposit_revertsWhenBeneficiary() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p1, AMOUNT);

        vm.prank(p1);
        vm.expectRevert(Pasanaku.Pasanaku__CannotDeposit.selector);
        pasanaku.deposit(0);
    }

    function test_deposit_revertsWhenNotParticipant() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        address nonParticipant = makeAddr("nonParticipant");
        token.mint(nonParticipant, 1000e18);
        vm.prank(nonParticipant);
        token.approve(address(pasanaku), AMOUNT);

        vm.prank(nonParticipant);
        vm.expectRevert(Pasanaku.Pasanaku__CannotDeposit.selector);
        pasanaku.deposit(0);
    }

    function test_deposit_revertsWhenAlreadyDeposited() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, 2 * AMOUNT);

        vm.prank(p2);
        pasanaku.deposit(0);

        vm.prank(p2);
        vm.expectRevert(Pasanaku.Pasanaku__CannotDeposit.selector);
        pasanaku.deposit(0);
    }

    function test_deposit_revertsWhenGameEnded() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        _fundAndApprove(p1, AMOUNT);
        vm.prank(p1);
        pasanaku.claim(0);

        _fundAndApprove(p1, AMOUNT);
        vm.prank(p1);
        pasanaku.deposit(0);

        vm.prank(p2);
        pasanaku.claim(0);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        vm.expectRevert(Pasanaku.Pasanaku__CannotDeposit.selector);
        pasanaku.deposit(0);
    }

    function test_claim_success() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        uint256 balanceBefore = token.balanceOf(p1);

        vm.expectEmit(true, true, false, true);
        emit Claimed(p1, 0, 0, AMOUNT, 0);

        vm.prank(p1);
        pasanaku.claim(0);

        assertEq(token.balanceOf(p1), balanceBefore + AMOUNT);
        assertEq(pasanaku.totalDeposited(0), 0);
        assertEq(pasanaku.rotatingSavings(0).currentIndex, 1);
    }

    function test_claim_lastParticipant_setsEnded() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.prank(p1);
        pasanaku.claim(0);

        _fundAndApprove(p1, AMOUNT);
        vm.prank(p1);
        pasanaku.deposit(0);

        vm.expectEmit(true, false, false, false);
        emit Ended(0, block.timestamp);

        vm.prank(p2);
        pasanaku.claim(0);

        assertTrue(pasanaku.rotatingSavings(0).ended);
        assertEq(pasanaku.beneficiary(0), address(0));
    }

    function test_claim_threeParticipants_firstRound() public {
        address[] memory participants = new address[](3);
        participants[0] = p1;
        participants[1] = p2;
        participants[2] = p3;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        _fundAndApprove(p3, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);
        vm.prank(p3);
        pasanaku.deposit(0);

        assertEq(pasanaku.totalDeposited(0), 2 * AMOUNT);
        assertTrue(pasanaku.canClaim(p1, 0));

        vm.prank(p1);
        pasanaku.claim(0);

        assertEq(pasanaku.rotatingSavings(0).currentIndex, 1);
        assertEq(pasanaku.totalDeposited(0), 0);
    }

    function test_claim_revertsWhenNotBeneficiary() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.prank(p2);
        vm.expectRevert(Pasanaku.Pasanaku__CannotClaim.selector);
        pasanaku.claim(0);
    }

    function test_claim_revertsWhenInsufficientDeposits() public {
        address[] memory participants = new address[](3);
        participants[0] = p1;
        participants[1] = p2;
        participants[2] = p3;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.prank(p1);
        vm.expectRevert(Pasanaku.Pasanaku__CannotClaim.selector);
        pasanaku.claim(0);
    }

    function test_claim_revertsWhenGameEnded() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.prank(p1);
        pasanaku.claim(0);

        _fundAndApprove(p1, AMOUNT);
        vm.prank(p1);
        pasanaku.deposit(0);

        vm.prank(p2);
        pasanaku.claim(0);

        vm.prank(p1);
        vm.expectRevert(Pasanaku.Pasanaku__CannotClaim.selector);
        pasanaku.claim(0);
    }

    /*//////////////////////////////////////////////////////////////
                              5. recover()
    //////////////////////////////////////////////////////////////*/

    function test_recover_success() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.warp(block.timestamp + 31 days);

        uint256 balanceBefore = token.balanceOf(p2);
        uint256 nftBalanceBefore = pasanaku.balanceOf(p2, 0);

        vm.expectEmit(true, true, false, true);
        emit Recovered(p2, 0, 0, AMOUNT);

        vm.prank(p2);
        pasanaku.recover(0);

        assertEq(token.balanceOf(p2), balanceBefore + AMOUNT);
        assertEq(pasanaku.balanceOf(p2, 0), nftBalanceBefore - 1);
        assertEq(pasanaku.totalDeposited(0), 0);
        assertFalse(pasanaku.hasDeposited(p2, 0));
    }

    function test_recover_revertsWhenBeneficiary() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.warp(block.timestamp + 31 days);

        vm.prank(p1);
        vm.expectRevert(Pasanaku.Pasanaku__CannotRecover.selector);
        pasanaku.recover(0);
    }

    function test_recover_revertsWhenNotDeposited() public {
        address[] memory participants = new address[](3);
        participants[0] = p1;
        participants[1] = p2;
        participants[2] = p3;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.warp(block.timestamp + 31 days);

        vm.prank(p3);
        vm.expectRevert(Pasanaku.Pasanaku__CannotRecover.selector);
        pasanaku.recover(0);
    }

    function test_recover_revertsBefore30Days() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.warp(block.timestamp + 29 days);

        vm.prank(p2);
        vm.expectRevert(Pasanaku.Pasanaku__CannotRecover.selector);
        pasanaku.recover(0);
    }

    function test_recover_revertsWhenNoDeposits() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        vm.warp(block.timestamp + 31 days);

        vm.prank(p2);
        vm.expectRevert(Pasanaku.Pasanaku__CannotRecover.selector);
        pasanaku.recover(0);
    }

    function test_recover_revertsWhenGameEnded() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.prank(p1);
        pasanaku.claim(0);

        _fundAndApprove(p1, AMOUNT);
        vm.prank(p1);
        pasanaku.deposit(0);

        vm.prank(p2);
        pasanaku.claim(0);

        vm.warp(block.timestamp + 31 days);

        vm.prank(p2);
        vm.expectRevert(Pasanaku.Pasanaku__CannotRecover.selector);
        pasanaku.recover(0);
    }

    /*//////////////////////////////////////////////////////////////
                        6. collectProtocolFees()
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                           7. VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_rotatingSavings_returnsCorrectState() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        IPasanaku.RotatingSavings memory rs = pasanaku.rotatingSavings(0);
        assertEq(rs.participants.length, 2);
        assertEq(rs.participants[0], p1);
        assertEq(rs.participants[1], p2);
        assertEq(rs.asset, address(token));
        assertEq(rs.amount, AMOUNT);
        assertEq(rs.currentIndex, 0);
        assertEq(rs.totalDeposited, 0);
        assertEq(rs.tokenId, 0);
        assertFalse(rs.ended);
        assertEq(rs.creator, owner);
    }

    function test_totalDeposited_returnsCorrectValue() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        assertEq(pasanaku.totalDeposited(0), 0);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        assertEq(pasanaku.totalDeposited(0), AMOUNT);
    }

    function test_expectedTotalDeposited() public {
        address[] memory participants = new address[](3);
        participants[0] = p1;
        participants[1] = p2;
        participants[2] = p3;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        assertEq(pasanaku.expectedTotalDeposited(0, p1), 2 * AMOUNT);
        assertEq(pasanaku.expectedTotalDeposited(0, p2), 2 * AMOUNT);
        assertEq(pasanaku.expectedTotalDeposited(0, p3), 2 * AMOUNT);
    }

    function test_beneficiary_returnsCurrentBeneficiary() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        assertEq(pasanaku.beneficiary(0), p1);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.prank(p1);
        pasanaku.claim(0);

        assertEq(pasanaku.beneficiary(0), p2);
    }

    function test_beneficiary_returnsZeroWhenEnded() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.prank(p1);
        pasanaku.claim(0);

        _fundAndApprove(p1, AMOUNT);
        vm.prank(p1);
        pasanaku.deposit(0);

        vm.prank(p2);
        pasanaku.claim(0);

        assertEq(pasanaku.beneficiary(0), address(0));
    }

    function test_canClaim_canDeposit_canRecover() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        assertFalse(pasanaku.canClaim(p1, 0));
        assertTrue(pasanaku.canDeposit(p2, 0));
        assertFalse(pasanaku.canRecover(p2, 0));

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        assertTrue(pasanaku.canClaim(p1, 0));
        assertFalse(pasanaku.canDeposit(p2, 0));
        assertFalse(pasanaku.canRecover(p2, 0));

        vm.warp(block.timestamp + 31 days);

        assertTrue(pasanaku.canRecover(p2, 0));
    }

    function test_participantsCount_returnsCorrectValue() public {
        address[] memory participants = new address[](3);
        participants[0] = p1;
        participants[1] = p2;
        participants[2] = p3;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        assertEq(pasanaku.participantsCount(0), 3);
    }

    function test_hasDeposited_returnsCorrectAfterDeposit() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        assertFalse(pasanaku.hasDeposited(p2, 0));

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        assertTrue(pasanaku.hasDeposited(p2, 0));
    }

    function test_integration_fullRotation_twoParticipants() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        _fundAndApprove(p1, AMOUNT);
        vm.prank(p1);
        pasanaku.claim(0);

        _fundAndApprove(p1, AMOUNT);
        vm.prank(p1);
        pasanaku.deposit(0);

        vm.prank(p2);
        pasanaku.claim(0);

        assertTrue(pasanaku.rotatingSavings(0).ended);
    }

    /// @dev With one deposit per participant per game, round 2 cannot collect enough deposits for N=3
    ///      (p2/p3 already used their deposit in round 0).
    function test_threeParticipants_stallsAfterFirstRound() public {
        address[] memory participants = new address[](3);
        participants[0] = p1;
        participants[1] = p2;
        participants[2] = p3;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        _fundAndApprove(p3, AMOUNT);

        vm.prank(p2);
        pasanaku.deposit(0);
        vm.prank(p3);
        pasanaku.deposit(0);

        vm.prank(p1);
        pasanaku.claim(0);

        assertEq(pasanaku.beneficiary(0), p2);
        assertTrue(pasanaku.hasDeposited(p2, 0));
        assertTrue(pasanaku.hasDeposited(p3, 0));
        assertFalse(pasanaku.hasDeposited(p1, 0));

        _fundAndApprove(p3, AMOUNT);
        vm.prank(p3);
        vm.expectRevert(Pasanaku.Pasanaku__CannotDeposit.selector);
        pasanaku.deposit(0);

        _fundAndApprove(p1, AMOUNT);
        vm.prank(p1);
        pasanaku.deposit(0);

        assertEq(pasanaku.totalDeposited(0), AMOUNT);
        assertFalse(pasanaku.canClaim(p2, 0));
    }

    function test_integration_recoverThenClaim() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.warp(block.timestamp + 31 days);

        vm.prank(p2);
        pasanaku.recover(0);

        assertFalse(pasanaku.canClaim(p1, 0));
        assertEq(pasanaku.totalDeposited(0), 0);
    }

    function test_uri_matchesTokenDescriptor() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        IPasanaku.RotatingSavings memory rs = pasanaku.rotatingSavings(0);
        assertEq(pasanaku.uri(0), tokenDescriptor.tokenURI(rs));
    }

    function test_uri_uninitializedTokenId_reverts() public {
        // Default `asset` is address(0); layouts read ERC20 metadata and revert.
        vm.expectRevert();
        pasanaku.uri(999);
    }

    function test_uri_secondToken_matchesTokenDescriptor() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.startPrank(owner);
        pasanaku.create(address(token), participants, AMOUNT);
        pasanaku.create(address(token), participants, AMOUNT);
        vm.stopPrank();

        assertEq(pasanaku.uri(0), tokenDescriptor.tokenURI(pasanaku.rotatingSavings(0)));
        assertEq(pasanaku.uri(1), tokenDescriptor.tokenURI(pasanaku.rotatingSavings(1)));
    }

    function test_uri_returnsJsonDataUriPrefix() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        string memory u = pasanaku.uri(0);
        assertTrue(LibString.startsWith(u, "data:application/json;base64,"));
    }

    function test_uri_changesWhenRotatingSavingsStateChanges() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        string memory uriBefore = pasanaku.uri(0);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        string memory uriAfter = pasanaku.uri(0);
        assertTrue(keccak256(bytes(uriBefore)) != keccak256(bytes(uriAfter)));
        assertEq(uriAfter, tokenDescriptor.tokenURI(pasanaku.rotatingSavings(0)));
    }

    function test_recover_burnsCorrectAmount() public {
        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        assertEq(pasanaku.balanceOf(p2, 0), 1);

        _fundAndApprove(p2, AMOUNT);
        vm.prank(p2);
        pasanaku.deposit(0);

        vm.warp(block.timestamp + 31 days);

        vm.prank(p2);
        pasanaku.recover(0);

        assertEq(pasanaku.balanceOf(p2, 0), 0);
    }

    function test_create_withMaxParticipants() public {
        address[] memory participants = _createParticipants(12);

        vm.prank(owner);
        pasanaku.create(address(token), participants, AMOUNT);

        assertEq(pasanaku.participantsCount(0), 12);
        for (uint256 i; i < 12; i++) {
            assertEq(pasanaku.balanceOf(participants[i], 0), 1);
        }
    }

    function test_nonExistentTokenId_returnsEmptyState() public view {
        IPasanaku.RotatingSavings memory rs = pasanaku.rotatingSavings(999);
        assertEq(rs.creator, address(0));
    }

    function test_deposit_revertsOnReentrantToken() public {
        ReentrantMockERC20 reToken = new ReentrantMockERC20("Reentrant", "RNT", 18);
        reToken.mint(p2, 1000e18);

        address[SUPPORTED_ASSETS_COUNT] memory assets;
        assets[0] = address(reToken);
        for (uint256 i = 1; i < SUPPORTED_ASSETS_COUNT; i++) {
            assets[i] = address(0);
        }

        vm.prank(owner);
        Pasanaku p = new Pasanaku(assets, address(tokenDescriptor));

        address[] memory participants = new address[](2);
        participants[0] = p1;
        participants[1] = p2;

        vm.prank(owner);
        p.create(address(reToken), participants, AMOUNT);

        reToken.setReenterDeposit(p, 0, p2);

        vm.prank(p2);
        reToken.approve(address(p), AMOUNT);

        vm.prank(p2);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        p.deposit(0);
    }
}
