// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

/// @notice Minimal ERC20 metadata interface for layout contracts.
interface IERC20Metadata {
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
}
