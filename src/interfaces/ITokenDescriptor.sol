// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {IPasanaku} from "./IPasanaku.sol";

/// @notice Interface for token descriptor.
interface ITokenDescriptor {
    function tokenURI(IPasanaku.RotatingSavings memory rs) external view returns (string memory);
}
