// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LayoutOngoing} from "pasanaku/metadata/layouts/LayoutOngoing.sol";
import {IPasanaku} from "pasanaku/interfaces/IPasanaku.sol";
import {MockERC20Metadata} from "tests/_mocks/MockERC20Metadata.sol";

contract LayoutOngoingTest is Test {
    LayoutOngoing public layoutOngoing;
    MockERC20Metadata public token;

    address public creator;
    address[] public participants;

    uint256 constant DATA_URI_PREFIX_LEN = 26; // "data:image/svg+xml;base64,"

    function setUp() public {
        layoutOngoing = new LayoutOngoing();
        token = new MockERC20Metadata(18, "USDC");
        creator = makeAddr("creator");

        participants = new address[](3);
        participants[0] = makeAddr("p1");
        participants[1] = makeAddr("p2");
        participants[2] = makeAddr("p3");
    }

    function _createRs(
        address asset,
        uint256 amount,
        address creator_,
        uint256 tokenId,
        address[] memory participants_,
        uint256 currentIndex,
        uint256 totalDeposited,
        bool ended
    ) internal view returns (IPasanaku.RotatingSavings memory rs) {
        rs = IPasanaku.RotatingSavings({
            participants: participants_,
            asset: asset,
            amount: amount,
            currentIndex: currentIndex,
            totalDeposited: totalDeposited,
            tokenId: tokenId,
            ended: ended,
            started: true,
            cancelled: false,
            creator: creator_,
            createdAt: block.timestamp,
            lastUpdatedAt: block.timestamp,
            minParticipants: 2,
            maxParticipants: 12
        });
    }

    function _decodeSvg(string memory dataUri) internal pure returns (string memory) {
        bytes memory full = bytes(dataUri);
        require(full.length > DATA_URI_PREFIX_LEN, "LayoutOngoingTest: invalid data uri");
        bytes memory b64 = new bytes(full.length - DATA_URI_PREFIX_LEN);
        for (uint256 i = 0; i < b64.length; i++) {
            b64[i] = full[i + DATA_URI_PREFIX_LEN];
        }
        return string(Base64.decode(string(b64)));
    }

    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);
        if (needleBytes.length > haystackBytes.length) return false;
        for (uint256 i = 0; i <= haystackBytes.length - needleBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function test_layout_returnsValidDataUri() public view {
        IPasanaku.RotatingSavings memory rs = _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = layoutOngoing.layout(rs);

        assertTrue(
            _contains(result, "data:image/svg+xml;base64,"), "LayoutOngoing: output should start with data URI prefix"
        );
    }

    function test_layout_svgContainsSymbol() public view {
        IPasanaku.RotatingSavings memory rs = _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = layoutOngoing.layout(rs);
        string memory svg = _decodeSvg(result);

        assertTrue(_contains(svg, "USDC"), "LayoutOngoing: SVG should contain symbol");
        assertTrue(_contains(svg, "Currency"), "LayoutOngoing: SVG should contain Currency label");
    }

    function test_layout_svgContainsTotalAmount() public view {
        IPasanaku.RotatingSavings memory rs = _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = layoutOngoing.layout(rs);
        string memory svg = _decodeSvg(result);

        assertTrue(_contains(svg, "2"), "LayoutOngoing: SVG should contain total amount (2)");
        assertTrue(_contains(svg, "Total Amount"), "LayoutOngoing: SVG should contain label");
    }

    function test_layout_svgContainsRoundInfo() public view {
        // currentIndex=1 => round 2, 3 players => 2/3
        IPasanaku.RotatingSavings memory rs = _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = layoutOngoing.layout(rs);
        string memory svg = _decodeSvg(result);

        assertTrue(_contains(svg, "2/3"), "LayoutOngoing: SVG should contain round 2/3");
        assertTrue(_contains(svg, "Round"), "LayoutOngoing: SVG should contain Round label");
    }

    function test_layout_svgContainsDepositedInfo() public view {
        // 3 players, 2 deposited: playersDeposited=2, playersExpected=2 => "2 of 2"
        IPasanaku.RotatingSavings memory rs = _createRs(address(token), 1e18, creator, 42, participants, 0, 2e18, false);

        string memory result = layoutOngoing.layout(rs);
        string memory svg = _decodeSvg(result);

        assertTrue(_contains(svg, "2 of 2"), "LayoutOngoing: SVG should contain 2 of 2");
        assertTrue(_contains(svg, "Deposited"), "LayoutOngoing: SVG should contain Deposited label");
    }

    function test_layout_svgContainsPlayersAndTokenId() public view {
        IPasanaku.RotatingSavings memory rs = _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = layoutOngoing.layout(rs);
        string memory svg = _decodeSvg(result);

        assertTrue(_contains(svg, "3"), "LayoutOngoing: SVG should contain players count");
        assertTrue(_contains(svg, "Players"), "LayoutOngoing: SVG should contain Players label");
        assertTrue(_contains(svg, "PASANAKU #"), "LayoutOngoing: SVG should contain PASANAKU #");
        assertTrue(_contains(svg, "42"), "LayoutOngoing: SVG should contain tokenId 42");
    }

    function test_layout_roundOne() public {
        // currentIndex=0 => round 1, 5 players => 1/5
        address[] memory five = new address[](5);
        five[0] = makeAddr("player0");
        five[1] = makeAddr("player1");
        five[2] = makeAddr("player2");
        five[3] = makeAddr("player3");
        five[4] = makeAddr("player4");

        IPasanaku.RotatingSavings memory rs = _createRs(address(token), 1e18, creator, 1, five, 0, 1e18, false);

        string memory svg = _decodeSvg(layoutOngoing.layout(rs));

        assertTrue(_contains(svg, "1/5"), "LayoutOngoing: Round 1 should show 1/5");
    }

    function test_layout_partialDeposits() public {
        // 3 players, 2 deposited: totalDeposited=2e18, amount=1e18 => 2 of 2
        address[] memory three = new address[](3);
        three[0] = makeAddr("a");
        three[1] = makeAddr("b");
        three[2] = makeAddr("c");

        IPasanaku.RotatingSavings memory rs = _createRs(address(token), 1e18, creator, 1, three, 0, 2e18, false);

        string memory svg = _decodeSvg(layoutOngoing.layout(rs));

        assertTrue(_contains(svg, "2 of 2"), "LayoutOngoing: 2 deposited of 3 players (expected 2)");
    }

    function test_layout_differentDecimalsAndSymbols() public {
        MockERC20Metadata token6 = new MockERC20Metadata(6, "USDT");
        MockERC20Metadata token18 = new MockERC20Metadata(18, "DAI");

        address[] memory two = new address[](2);
        two[0] = makeAddr("a");
        two[1] = makeAddr("b");

        IPasanaku.RotatingSavings memory rs6 = _createRs(address(token6), 1e6, creator, 1, two, 0, 1e6, false);
        IPasanaku.RotatingSavings memory rs18 = _createRs(address(token18), 1e18, creator, 2, two, 0, 1e18, false);

        assertTrue(_contains(_decodeSvg(layoutOngoing.layout(rs6)), "USDT"));
        assertTrue(_contains(_decodeSvg(layoutOngoing.layout(rs18)), "DAI"));
    }

    function test_layout_revertsWithZeroAmount() public {
        IPasanaku.RotatingSavings memory rs = _createRs(address(token), 0, creator, 1, participants, 0, 0, false);

        vm.expectRevert();
        layoutOngoing.layout(rs);
    }
}
