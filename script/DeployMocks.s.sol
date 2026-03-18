// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockERC20} from "../test/_mocks/MockERC20.sol";

/// @title DeployMocks
/// @notice Deploys mock ERC20 tokens for testnet testing.
/// @dev Set MOCK_TOKENS env var for custom config: "name,symbol,decimals:name,symbol,decimals"
///      Example: MOCK_TOKENS="USDC,USDC,6:USDT,Tether,6:DAI,DAI,18"
///      Default: USDC (6 decimals), DAI (18 decimals)
contract DeployMocks is Script {
    uint256 private constant DEFAULT_MINT_AMOUNT = 1_000_000e18;

    function run() public returns (address[] memory deployed) {
        string memory config = vm.envOr("MOCK_TOKENS", string("USDC,USDC,6:DAI,DAI,18"));
        string[] memory tokens = vm.split(config, ":");
        deployed = new address[](tokens.length);

        for (uint256 i; i < tokens.length;) {
            string[] memory parts = vm.split(tokens[i], ",");
            require(parts.length == 3, "DeployMocks: invalid token config (need name,symbol,decimals)");

            string memory name = parts[0];
            string memory symbol = parts[1];
            uint8 decimals = uint8(vm.parseUint(parts[2]));

            vm.startBroadcast();

            MockERC20 token = new MockERC20(name, symbol, decimals);
            uint256 mintAmount = decimals == 18 ? DEFAULT_MINT_AMOUNT : 1_000_000 * (10 ** decimals);
            token.mint(msg.sender, mintAmount);

            vm.stopBroadcast();

            deployed[i] = address(token);
            console.log("Deployed MockERC20:", symbol, "at", deployed[i]);
            console.log("  Minted", mintAmount, "to", msg.sender);

            unchecked {
                ++i;
            }
        }

        return deployed;
    }
}
