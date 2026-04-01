// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

/// @notice Shared struct for rotating savings data.
/// @custom:security-contact https://x.com/rabuawad_
interface IPasanaku {
    function count() external view returns (uint256);
    function increment() external;
    function decrement() external;
    function reset() external;

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
        uint8 minParticipants;
        uint8 maxParticipants;
    }
}
