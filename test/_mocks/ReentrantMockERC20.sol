// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {MockERC20} from "./MockERC20.sol";
import {Pasanaku} from "pasanaku/Pasanaku.sol";

/// @notice ERC20 that re-enters `Pasanaku.deposit` during `transferFrom` for reentrancy tests.
contract ReentrantMockERC20 is MockERC20 {
    Pasanaku private _target;
    uint256 private _reenterTokenId;
    address private _reenterFrom;
    bool public reenterEnabled;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_, decimals_) {}

    function setReenterDeposit(Pasanaku target_, uint256 tokenId_, address from_) external {
        _target = target_;
        _reenterTokenId = tokenId_;
        _reenterFrom = from_;
        reenterEnabled = true;
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal override {
        if (!reenterEnabled) return;
        if (address(_target) == address(0)) return;
        if (to != address(_target)) return;
        if (from != _reenterFrom) return;
        _target.deposit(_reenterTokenId);
    }
}
