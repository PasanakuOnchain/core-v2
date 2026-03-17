// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";
import {IPasanaku} from "../interfaces/IPasanaku.sol";
import {ILayout} from "../interfaces/ILayout.sol";

contract TokenDescriptor {
    ILayout public immutable LAYOUT_ENDED;
    ILayout public immutable LAYOUT_ONGOING;

    constructor(address _layoutEnded, address _layoutOngoing) {
        LAYOUT_ENDED = ILayout(_layoutEnded);
        LAYOUT_ONGOING = ILayout(_layoutOngoing);
    }

    function tokenURI(IPasanaku.RotatingSavings memory rs) public view returns (string memory) {
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
            '{"trait_type": "Recovered", "value": ',
            rs.recovered ? "true" : "false",
            "},",
            '{"trait_type": "Creator", "value": "',
            LibString.toHexString(uint256(uint160(rs.creator)), 20),
            '"},',
            '{"trait_type": "Created At", "value": "',
            LibString.toString(rs.createdAt),
            '"},',
            '{"trait_type": "Last Updated At", "value": "',
            LibString.toString(rs.lastUpdatedAt),
            '"},',
            '{"trait_type": "Participants", "value": "',
            LibString.toString(rs.participants.length),
            '"},',
            '{"trait_type": "Asset", "value": "',
            LibString.toHexString(uint256(uint160(rs.asset)), 20),
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
