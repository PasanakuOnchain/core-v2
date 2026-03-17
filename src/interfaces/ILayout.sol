// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.33;

import {IPasanaku} from "./IPasanaku.sol";

interface ILayout {
    function layout(IPasanaku.RotatingSavings memory rotatingSavings) external view returns (string memory);
}
