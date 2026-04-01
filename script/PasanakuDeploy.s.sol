// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {IPasanaku} from "pasanaku/interfaces/IPasanaku.sol";

contract PasanakuDeploy is Script {
    IPasanaku public pasanaku;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        pasanaku = IPasanaku(deployCode("src/Pasanaku.vy"));

        require(pasanaku.count() == 0, "Count failed");

        pasanaku.increment();
        require(pasanaku.count() == 1, "Increment failed");

        pasanaku.decrement();
        require(pasanaku.count() == 0, "Decrement failed");

        pasanaku.increment();
        pasanaku.increment();
        pasanaku.increment();
        pasanaku.increment();
        pasanaku.increment();
        require(pasanaku.count() == 5, "Increment failed");

        pasanaku.reset();
        require(pasanaku.count() == 0, "Reset failed");
        vm.stopBroadcast();
    }
}
