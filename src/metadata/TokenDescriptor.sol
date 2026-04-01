// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";
import {IPasanaku} from "pasanaku/interfaces/IPasanaku.sol";
import {ILayout} from "pasanaku/interfaces/ILayout.sol";
import {ITokenDescriptor} from "pasanaku/interfaces/ITokenDescriptor.sol";

/// @custom:security-contact https://x.com/rabuawad_
contract TokenDescriptor is ITokenDescriptor {
    ILayout public immutable LAYOUT_ENDED;
    ILayout public immutable LAYOUT_ONGOING;

    uint256 private constant ADDRESS_LENGTH = 20;

    constructor(address _layoutEnded, address _layoutOngoing) {
        LAYOUT_ENDED = ILayout(_layoutEnded);
        LAYOUT_ONGOING = ILayout(_layoutOngoing);
    }

    function tokenURI(IPasanaku.RotatingSavings memory rs) external view returns (string memory) {
        string memory imageURI = rs.ended ? LAYOUT_ENDED.layout(rs) : LAYOUT_ONGOING.layout(rs);

        string memory dataURI = string.concat(
            '{"name": "Pasanaku #',
            LibString.toString(rs.tokenId),
            '", "description": "A rotating savings protocol onchain, deployed on the Arbitrum network.", "image": "',
            imageURI,
            '", "attributes": [',
            '{"trait_type": "Total Deposited", "value": "',
            LibString.toString(rs.totalDeposited),
            '"},',
            '{"trait_type": "Current Index", "value": "',
            LibString.toString(rs.currentIndex),
            '"},',
            '{"trait_type": "Ended", "value": ',
            rs.ended ? "true" : "false",
            "},",
            '{"trait_type": "Started", "value": ',
            rs.started ? "true" : "false",
            "},",
            '{"trait_type": "Cancelled", "value": ',
            rs.cancelled ? "true" : "false",
            "},",
            '{"trait_type": "Creator", "value": "',
            LibString.toHexString(uint256(uint160(rs.creator)), ADDRESS_LENGTH),
            '"},',
            '{"trait_type": "Created At", "value": "',
            LibString.toString(rs.createdAt),
            '"},',
            '{"trait_type": "Last Updated At", "value": "',
            LibString.toString(rs.lastUpdatedAt),
            '"},',
            '{"trait_type": "Starts At", "value": "',
            LibString.toString(rs.startsAt),
            '"},',
            '{"trait_type": "Cycle Epoch", "value": "',
            LibString.toString(rs.cycleEpoch),
            '"},',
            '{"trait_type": "Participants", "value": "',
            LibString.toString(rs.participants.length),
            '"},',
            '{"trait_type": "Asset", "value": "',
            LibString.toHexString(uint256(uint160(rs.asset)), ADDRESS_LENGTH),
            '"},',
            '{"trait_type": "Amount", "value": "',
            LibString.toString(rs.amount),
            '"},',
            '{"trait_type": "Token ID", "value": "',
            LibString.toString(rs.tokenId),
            '"}]}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(dataURI)));
    }
}
