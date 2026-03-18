// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

/// @notice Shared struct for rotating savings data.
library IPasanaku {
    struct RotatingSavings {
        address[] participants;
        address asset;
        uint256 amount;
        uint256 currentIndex;
        uint256 totalDeposited;
        uint256 tokenId;
        bool ended;
        bool recovered;
        address creator;
        uint256 createdAt;
        uint256 lastUpdatedAt;
    }
}
