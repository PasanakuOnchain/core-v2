// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Pasanaku} from "../src/Pasanaku.sol";
import {TokenDescriptor} from "../src/metadata/TokenDescriptor.sol";
import {LayoutEnded} from "../src/metadata/layouts/LayoutEnded.sol";
import {LayoutOngoing} from "../src/metadata/layouts/LayoutOngoing.sol";

/// @title Deploy
/// @notice Deploys TokenDescriptor (with layouts) and Pasanaku with modular asset configuration.
/// @dev Set ASSETS env var: comma-separated ERC20 addresses (up to 10 supported).
///      Example: ASSETS=0x123...,0x456...,0x789...
///      Unused slots are padded with address(0).
contract Deploy is Script {
    uint256 private constant SUPPORTED_ASSETS_COUNT = 10;

    function run() public returns (address pasanaku) {
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

        LayoutEnded layoutEnded = new LayoutEnded();
        LayoutOngoing layoutOngoing = new LayoutOngoing();
        TokenDescriptor tokenDescriptor = new TokenDescriptor(address(layoutEnded), address(layoutOngoing));
        pasanaku = address(new Pasanaku(assets, address(tokenDescriptor)));

        vm.stopBroadcast();

        console.log("Deployed LayoutEnded at", address(layoutEnded));
        console.log("Deployed LayoutOngoing at", address(layoutOngoing));
        console.log("Deployed TokenDescriptor at", address(tokenDescriptor));
        console.log("Deployed Pasanaku at", pasanaku);
        console.log("  Owner:", Pasanaku(payable(pasanaku)).owner());
        for (uint256 i; i < assetsRaw.length;) {
            console.log("  Asset", i, ":", assets[i]);
            unchecked {
                ++i;
            }
        }

        return pasanaku;
    }
}
