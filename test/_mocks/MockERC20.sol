// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {ERC20} from "solady/tokens/ERC20.sol";

/// @notice Mock ERC20 for Pasanaku tests. Extends Solady ERC20 with mint capability.
contract MockERC20 is ERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
