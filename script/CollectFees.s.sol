// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Pasanaku} from "pasanaku/Pasanaku.sol";

/// @title CollectFees
/// @notice Collects protocol fees from an existing Pasanaku instance.
/// @dev Requires PASANAKU_ADDRESS env var. Caller must be the contract owner.
contract CollectFees is Script {
    function run() public {
        address payable pasanakuAddress = payable(vm.envAddress("PASANAKU_ADDRESS"));
        uint256 contractBalance = pasanakuAddress.balance;

        vm.startBroadcast();
        Pasanaku(payable(pasanakuAddress)).collectProtocolFees();
        vm.stopBroadcast();

        console.log("CollectFees: success");
        console.log("  Pasanaku contract ETH collected:", contractBalance);
    }
}
