// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

/// @notice Shared struct for rotating savings data.
/// @custom:security-contact https://x.com/rabuawad_
interface IPasanaku {
    struct RotatingSavings {
        address[] participants;
        address asset;
        uint256 amount;
        uint256 currentIndex;
        uint256 totalDeposited;
        uint256 tokenId;
        bool ended;
        bool started;
        bool cancelled;
        address creator;
        uint256 createdAt;
        uint256 lastUpdatedAt;
        uint256 startsAt;
        uint256 cycleEpoch;
        uint8 maxParticipants;
    }
}
