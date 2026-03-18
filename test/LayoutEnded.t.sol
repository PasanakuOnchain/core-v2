// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LayoutEnded} from "../src/metadata/layouts/LayoutEnded.sol";
import {IPasanaku} from "../src/interfaces/IPasanaku.sol";
import {MockERC20Metadata} from "./_mocks/MockERC20Metadata.sol";

contract LayoutEndedTest is Test {
    LayoutEnded public layoutEnded;
    MockERC20Metadata public token;

    address public creator;
    address[] public participants;

    uint256 constant DATA_URI_PREFIX_LEN = 26; // "data:image/svg+xml;base64,"

    function setUp() public {
        layoutEnded = new LayoutEnded();
        token = new MockERC20Metadata(18, "USDC");
        creator = makeAddr("creator");

        participants = new address[](3);
        participants[0] = makeAddr("p1");
        participants[1] = makeAddr("p2");
        participants[2] = makeAddr("p3");
    }

    function _createRS(
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
            recovered: false,
            creator: creator_,
            createdAt: block.timestamp,
            lastUpdatedAt: block.timestamp
        });
    }

    function _decodeSvg(string memory dataUri) internal pure returns (string memory) {
        bytes memory full = bytes(dataUri);
        require(full.length > DATA_URI_PREFIX_LEN, "LayoutEndedTest: invalid data uri");
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
        IPasanaku.RotatingSavings memory rs =
            _createRS(address(token), 1e18, creator, 42, participants, 2, 3e18, true);

        string memory result = layoutEnded.layout(rs);

        assertTrue(
            _contains(result, "data:image/svg+xml;base64,"),
            "LayoutEnded: output should start with data URI prefix"
        );
    }

    function test_layout_svgContainsCreatorAddress() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRS(address(token), 1e18, creator, 42, participants, 2, 3e18, true);

        string memory result = layoutEnded.layout(rs);
        string memory svg = _decodeSvg(result);

        assertTrue(_contains(svg, "0x2190..cbe8"), "LayoutEnded: SVG should contain abbreviated creator");
    }

    function test_layout_svgContainsPlayersCount() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRS(address(token), 1e18, creator, 42, participants, 2, 3e18, true);

        string memory result = layoutEnded.layout(rs);
        string memory svg = _decodeSvg(result);

        assertTrue(_contains(svg, "3"), "LayoutEnded: SVG should contain players count");
        assertTrue(_contains(svg, "Players"), "LayoutEnded: SVG should contain Players label");
    }

    function test_layout_svgContainsTotalDistributed() public view {
        // 3 players: totalDistributed = amount * (3-1) * 3 = 6e18
        IPasanaku.RotatingSavings memory rs =
            _createRS(address(token), 1e18, creator, 42, participants, 2, 3e18, true);

        string memory result = layoutEnded.layout(rs);
        string memory svg = _decodeSvg(result);

        assertTrue(_contains(svg, "6"), "LayoutEnded: SVG should contain total distributed (6)");
        assertTrue(_contains(svg, "Total distributed"), "LayoutEnded: SVG should contain label");
        assertTrue(_contains(svg, "USDC"), "LayoutEnded: SVG should contain symbol");
    }

    function test_layout_svgContainsTokenId() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRS(address(token), 1e18, creator, 42, participants, 2, 3e18, true);

        string memory result = layoutEnded.layout(rs);
        string memory svg = _decodeSvg(result);

        assertTrue(_contains(svg, "PASANAKU #"), "LayoutEnded: SVG should contain PASANAKU #");
        assertTrue(_contains(svg, "42"), "LayoutEnded: SVG should contain tokenId 42");
    }

    function test_layout_differentDecimals() public {
        MockERC20Metadata token6 = new MockERC20Metadata(6, "USDC");
        MockERC20Metadata token18 = new MockERC20Metadata(18, "WETH");

        // 2 players: totalDistributed = 1e6 * 1 * 2 = 2e6
        IPasanaku.RotatingSavings memory rs6 =
            _createRS(address(token6), 1e6, creator, 1, participants, 1, 1e6, true);
        participants[0] = makeAddr("a");
        participants[1] = makeAddr("b");
        address[] memory twoPlayers = new address[](2);
        twoPlayers[0] = participants[0];
        twoPlayers[1] = participants[1];

        rs6.participants = twoPlayers;

        string memory result6 = layoutEnded.layout(rs6);
        string memory svg6 = _decodeSvg(result6);

        // 2 players: totalDistributed = 1e18 * 1 * 2 = 2e18
        IPasanaku.RotatingSavings memory rs18 =
            _createRS(address(token18), 1e18, creator, 2, twoPlayers, 1, 1e18, true);

        string memory result18 = layoutEnded.layout(rs18);
        string memory svg18 = _decodeSvg(result18);

        assertTrue(_contains(svg6, "2"), "LayoutEnded: 6 decimals should show 2");
        assertTrue(_contains(svg6, "USDC"), "LayoutEnded: should show USDC");
        assertTrue(_contains(svg18, "2"), "LayoutEnded: 18 decimals should show 2");
        assertTrue(_contains(svg18, "WETH"), "LayoutEnded: should show WETH");
    }

    function test_layout_differentSymbols() public {
        MockERC20Metadata usdt = new MockERC20Metadata(6, "USDT");
        MockERC20Metadata dai = new MockERC20Metadata(18, "DAI");

        address[] memory two = new address[](2);
        two[0] = makeAddr("a");
        two[1] = makeAddr("b");

        IPasanaku.RotatingSavings memory rsUsdt =
            _createRS(address(usdt), 1e6, creator, 1, two, 0, 1e6, true);
        IPasanaku.RotatingSavings memory rsDai =
            _createRS(address(dai), 1e18, creator, 2, two, 0, 1e18, true);

        assertTrue(_contains(_decodeSvg(layoutEnded.layout(rsUsdt)), "USDT"));
        assertTrue(_contains(_decodeSvg(layoutEnded.layout(rsDai)), "DAI"));
    }

    function test_layout_twoPlayers() public {
        address[] memory two = new address[](2);
        two[0] = makeAddr("a");
        two[1] = makeAddr("b");

        // totalDistributed = 100e18 * (2-1) * 2 = 200e18
        IPasanaku.RotatingSavings memory rs =
            _createRS(address(token), 100e18, creator, 1, two, 0, 100e18, true);

        string memory svg = _decodeSvg(layoutEnded.layout(rs));

        assertTrue(_contains(svg, "200"), "LayoutEnded: 2 players should show 200");
    }

    function test_layout_manyPlayers() public {
        address[] memory five = new address[](5);
        five[0] = makeAddr("player0");
        five[1] = makeAddr("player1");
        five[2] = makeAddr("player2");
        five[3] = makeAddr("player3");
        five[4] = makeAddr("player4");

        // totalDistributed = 10e18 * (5-1) * 5 = 200e18
        IPasanaku.RotatingSavings memory rs =
            _createRS(address(token), 10e18, creator, 1, five, 2, 30e18, true);

        string memory svg = _decodeSvg(layoutEnded.layout(rs));

        assertTrue(_contains(svg, "200"), "LayoutEnded: 5 players should show 200");
        assertTrue(_contains(svg, "5"), "LayoutEnded: should show 5 players");
    }

    function test_layout_revertsWithZeroParticipants() public {
        address[] memory empty;
        IPasanaku.RotatingSavings memory rs =
            _createRS(address(token), 1e18, creator, 1, empty, 0, 0, true);

        vm.expectRevert();
        layoutEnded.layout(rs);
    }
}
