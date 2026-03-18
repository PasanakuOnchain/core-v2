// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";
import {TokenDescriptor} from "../src/metadata/TokenDescriptor.sol";
import {LayoutEnded} from "../src/metadata/layouts/LayoutEnded.sol";
import {LayoutOngoing} from "../src/metadata/layouts/LayoutOngoing.sol";
import {IPasanaku} from "../src/interfaces/IPasanaku.sol";
import {MockERC20Metadata} from "./_mocks/MockERC20Metadata.sol";

contract TokenDescriptorTest is Test {
    TokenDescriptor public tokenDescriptor;
    LayoutEnded public layoutEnded;
    LayoutOngoing public layoutOngoing;
    MockERC20Metadata public token;

    address public creator;
    address[] public participants;

    uint256 constant JSON_DATA_URI_PREFIX_LEN = 29; // "data:application/json;base64,"

    function setUp() public {
        layoutEnded = new LayoutEnded();
        layoutOngoing = new LayoutOngoing();
        tokenDescriptor = new TokenDescriptor(address(layoutEnded), address(layoutOngoing));
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
            recovered: false,
            creator: creator_,
            createdAt: block.timestamp,
            lastUpdatedAt: block.timestamp
        });
    }

    function _decodeJsonPayload(string memory dataUri) internal pure returns (string memory) {
        bytes memory full = bytes(dataUri);
        require(full.length > JSON_DATA_URI_PREFIX_LEN, "TokenDescriptorTest: invalid data uri");
        bytes memory b64 = new bytes(full.length - JSON_DATA_URI_PREFIX_LEN);
        for (uint256 i = 0; i < b64.length; i++) {
            b64[i] = full[i + JSON_DATA_URI_PREFIX_LEN];
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

    // -------------------------------------------------------------------------
    // 1. Constructor and Immutables
    // -------------------------------------------------------------------------

    function test_constructor_setsLayouts() public view {
        assertEq(address(tokenDescriptor.LAYOUT_ENDED()), address(layoutEnded));
        assertEq(address(tokenDescriptor.LAYOUT_ONGOING()), address(layoutOngoing));
    }

    // -------------------------------------------------------------------------
    // 2. Output Format
    // -------------------------------------------------------------------------

    function test_tokenURI_returnsValidDataUriPrefix() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);

        assertTrue(
            _contains(result, "data:application/json;base64,"),
            "TokenDescriptor: output should start with data:application/json;base64,"
        );
    }

    function test_tokenURI_base64DecodesToValidJson() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, "name"), "JSON should contain name");
        assertTrue(_contains(json, "description"), "JSON should contain description");
        assertTrue(_contains(json, "image"), "JSON should contain image");
        assertTrue(_contains(json, "attributes"), "JSON should contain attributes");
    }

    // -------------------------------------------------------------------------
    // 3. Layout Delegation
    // -------------------------------------------------------------------------

    function test_tokenURI_usesLayoutOngoingWhenNotEnded() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(
            _contains(json, "data:image/svg+xml;base64,"),
            "Image should contain SVG data URI from LayoutOngoing"
        );
    }

    function test_tokenURI_usesLayoutEndedWhenEnded() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 2, 3e18, true);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(
            _contains(json, "data:image/svg+xml;base64,"),
            "Image should contain SVG data URI from LayoutEnded"
        );
    }

    // -------------------------------------------------------------------------
    // 4. JSON Structure and Fields
    // -------------------------------------------------------------------------

    function test_tokenURI_jsonHasRequiredFields() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, '"name"'), "JSON should contain name field");
        assertTrue(_contains(json, '"description"'), "JSON should contain description field");
        assertTrue(_contains(json, '"image"'), "JSON should contain image field");
        assertTrue(_contains(json, '"attributes"'), "JSON should contain attributes field");
    }

    function test_tokenURI_nameFormat() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, "Pasanaku #42"), "Name should be Pasanaku #42");
    }

    function test_tokenURI_description() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(
            _contains(json, "A rotating savings protocol onchain, deployed on the Arbitrum network."),
            "Description should match fixed Arbitrum string"
        );
    }

    function test_tokenURI_attributesCount() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        uint256 count = 0;
        bytes memory j = bytes(json);
        for (uint256 i = 0; i < j.length - 8; i++) {
            if (
                j[i] == "t" && j[i + 1] == "r" && j[i + 2] == "a" && j[i + 3] == "i"
                    && j[i + 4] == "t" && j[i + 5] == "_" && j[i + 6] == "t" && j[i + 7] == "y"
            ) {
                count++;
            }
        }
        assertEq(count, 11, "Should have 11 trait entries");
    }

    // -------------------------------------------------------------------------
    // 5. Attribute Values
    // -------------------------------------------------------------------------

    function test_tokenURI_attributeTotalDeposited() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, '"Total Deposited"'), "Should have Total Deposited trait");
        assertTrue(_contains(json, '"value": "2000000000000000000"'), "Total Deposited value should be 2e18");
    }

    function test_tokenURI_attributeCurrentIndex() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, '"Current Index"'), "Should have Current Index trait");
        assertTrue(_contains(json, '"value": "1"'), "Current Index value should be 1");
    }

    function test_tokenURI_attributeEnded() public view {
        IPasanaku.RotatingSavings memory rsFalse =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);
        IPasanaku.RotatingSavings memory rsTrue =
            _createRs(address(token), 1e18, creator, 42, participants, 2, 3e18, true);

        string memory jsonFalse = _decodeJsonPayload(tokenDescriptor.tokenURI(rsFalse));
        string memory jsonTrue = _decodeJsonPayload(tokenDescriptor.tokenURI(rsTrue));

        assertTrue(_contains(jsonFalse, '"Ended"'), "Should have Ended trait");
        assertTrue(_contains(jsonFalse, '"value": false'), "Ended should be false when not ended");
        assertTrue(_contains(jsonTrue, '"value": true'), "Ended should be true when ended");
    }

    function test_tokenURI_attributeRecovered() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);
        rs.recovered = true;

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, '"Recovered"'), "Should have Recovered trait");
        assertTrue(_contains(json, '"value": true'), "Recovered should be true");
    }

    function test_tokenURI_attributeCreator() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        string memory expectedCreatorHex = LibString.toHexString(uint256(uint160(creator)), 20);
        assertTrue(_contains(json, '"Creator"'), "Should have Creator trait");
        assertTrue(_contains(json, expectedCreatorHex), "Creator should be hex format");
    }

    function test_tokenURI_attributeCreatedAt() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, '"Created At"'), "Should have Created At trait");
        assertTrue(
            _contains(json, LibString.toString(block.timestamp)),
            "Created At should match block.timestamp"
        );
    }

    function test_tokenURI_attributeLastUpdatedAt() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, '"Last Updated At"'), "Should have Last Updated At trait");
        assertTrue(
            _contains(json, LibString.toString(block.timestamp)),
            "Last Updated At should match block.timestamp"
        );
    }

    function test_tokenURI_attributeParticipants() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, '"Participants"'), "Should have Participants trait");
        assertTrue(_contains(json, '"value": "3"'), "Participants should be 3");
    }

    function test_tokenURI_attributeAsset() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        string memory expectedAssetHex = LibString.toHexString(uint256(uint160(address(token))), 20);
        assertTrue(_contains(json, '"Asset"'), "Should have Asset trait");
        assertTrue(_contains(json, expectedAssetHex), "Asset should be hex format");
    }

    function test_tokenURI_attributeAmount() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, '"Amount"'), "Should have Amount trait");
        assertTrue(_contains(json, '"value": "1000000000000000000"'), "Amount value should be 1e18");
    }

    function test_tokenURI_attributeTokenId() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, '"Token ID"'), "Should have Token ID trait");
        assertTrue(_contains(json, '"value": "42"'), "Token ID value should be 42");
    }

    // -------------------------------------------------------------------------
    // 6. Edge Cases
    // -------------------------------------------------------------------------

    function test_tokenURI_minimalValidParticipants() public {
        address[] memory one = new address[](1);
        one[0] = makeAddr("sole");
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 1, one, 0, 1e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, '"value": "1"'), "Participants should be 1");
    }

    function test_tokenURI_recoveredTrue() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 42, participants, 1, 2e18, false);
        rs.recovered = true;

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, '"Recovered"'), "Should have Recovered trait");
        assertTrue(_contains(json, '"value": true'), "Recovered should be true");
    }

    function test_tokenURI_zeroTokenId() public view {
        IPasanaku.RotatingSavings memory rs =
            _createRs(address(token), 1e18, creator, 0, participants, 1, 2e18, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, "Pasanaku #0"), "Name should be Pasanaku #0");
        assertTrue(_contains(json, '"Token ID"'), "Should have Token ID trait");
        assertTrue(_contains(json, '"value": "0"'), "Token ID value should be 0");
    }

    function test_tokenURI_largeValues() public view {
        uint256 largeAmount = 1e18 * 1_000_000;
        uint256 largeTimestamp = 2_000_000_000;
        IPasanaku.RotatingSavings memory rs = _createRs(
            address(token), largeAmount, creator, 999_999, participants, 2, largeAmount * 3, false
        );
        rs.createdAt = largeTimestamp;
        rs.lastUpdatedAt = largeTimestamp;

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        assertTrue(_contains(json, LibString.toString(largeAmount)), "Should contain large amount");
        assertTrue(_contains(json, LibString.toString(largeTimestamp)), "Should contain large timestamp");
        assertTrue(_contains(json, "999999"), "Should contain large tokenId");
    }

    function test_tokenURI_differentAddresses() public {
        address creatorA = makeAddr("creatorA");
        MockERC20Metadata tokenB = new MockERC20Metadata(6, "USDT");
        address[] memory two = new address[](2);
        two[0] = makeAddr("a");
        two[1] = makeAddr("b");

        IPasanaku.RotatingSavings memory rs =
            _createRs(address(tokenB), 1e6, creatorA, 1, two, 0, 1e6, false);

        string memory result = tokenDescriptor.tokenURI(rs);
        string memory json = _decodeJsonPayload(result);

        string memory creatorHex = LibString.toHexString(uint256(uint160(creatorA)), 20);
        string memory assetHex = LibString.toHexString(uint256(uint160(address(tokenB))), 20);
        assertTrue(_contains(json, creatorHex), "Creator hex should match creatorA");
        assertTrue(_contains(json, assetHex), "Asset hex should match tokenB");
    }
}
