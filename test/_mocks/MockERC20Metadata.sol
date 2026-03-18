// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {IERC20Metadata} from "../../src/interfaces/IERC20Metadata.sol";

/// @notice Minimal mock implementing IERC20Metadata for layout contract tests.
contract MockERC20Metadata is IERC20Metadata {
    uint8 private _decimals;
    string private _symbol;

    constructor(uint8 decimals_, string memory symbol_) {
        _decimals = decimals_;
        _symbol = symbol_;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }
}
