// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPasanaku} from "pasanaku/interfaces/IPasanaku.sol";

/// @title Deploy
/// @notice Deploys Pasanaku with modular asset configuration.
/// @dev Set ASSETS env var: comma-separated ERC20 addresses (up to 10 supported).
///      Example: ASSETS=0x123...,0x456...,0x789...
///      Unused slots are padded with address(0).
contract Deploy is Script {
    uint256 private constant SUPPORTED_ASSETS_COUNT = 10;
    IPasanaku public pasanaku;

    function run() public returns (IPasanaku) {
        address[] memory assetsRaw = vm.envAddress("ASSETS", ",");
        require(assetsRaw.length <= SUPPORTED_ASSETS_COUNT, "Deploy: max 10 assets supported");

        address[SUPPORTED_ASSETS_COUNT] memory assets;
        for (uint256 i; i < SUPPORTED_ASSETS_COUNT;) {
            assets[i] = i < assetsRaw.length ? assetsRaw[i] : address(0);
            unchecked {
                ++i;
            }
        }

        vm.startBroadcast();
        pasanaku = IPasanaku(deployCode("src/Pasanaku.vy", abi.encode(assets)));
        vm.stopBroadcast();

        console.log("Deployed Pasanaku at", address(pasanaku));
        console.log(" Owner:", pasanaku.owner());
        for (uint256 i; i < assetsRaw.length;) {
            console.log("  Asset", i, ":", assets[i]);
            unchecked {
                ++i;
            }
        }

        return pasanaku;
    }
}
