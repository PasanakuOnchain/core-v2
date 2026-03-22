// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.33;

import {LibString} from "solady/utils/LibString.sol";

/// @notice Shared utilities for layout contracts.
/// @custom:security-contact https://x.com/rabuawad_
library LibLayoutUtils {
    /// @dev Formats a token amount with decimal places, trimming trailing zeros.
    /// @param value Raw token amount (e.g. 1500000000000000000 for 1.5 with 18 decimals).
    /// @param decimals Number of decimal places.
    function formatWithDecimals(uint256 value, uint256 decimals) internal pure returns (string memory) {
        uint256 divisor = 10 ** decimals;
        uint256 wholePart = value / divisor;
        uint256 fractionalPart = value % divisor;

        if (fractionalPart == 0) {
            return LibString.toString(wholePart);
        }

        string memory fractionalStr = LibString.toString(fractionalPart);
        uint256 digits = _digitCount(fractionalPart);
        uint256 padCount = decimals - digits;

        for (uint256 i; i < padCount; ++i) {
            fractionalStr = string.concat("0", fractionalStr);
        }

        bytes memory fracBytes = bytes(fractionalStr);
        uint256 end = fracBytes.length;
        while (end > 0 && fracBytes[end - 1] == 0x30) {
            end--;
        }
        if (end == 0) return LibString.toString(wholePart);

        bytes memory trimmed = new bytes(end);
        for (uint256 i = 0; i < end; i++) {
            trimmed[i] = fracBytes[i];
        }

        return string.concat(LibString.toString(wholePart), ".", string(trimmed));
    }

    /// @dev Returns address in abbreviated form: 0x1234..abcd
    function abbreviateAddress(address addr) internal pure returns (string memory) {
        string memory full = LibString.toHexString(uint256(uint160(addr)), 20);
        bytes memory fullBytes = bytes(full);
        bytes memory result = new bytes(12);
        result[0] = fullBytes[0];
        result[1] = fullBytes[1];
        result[2] = fullBytes[2];
        result[3] = fullBytes[3];
        result[4] = fullBytes[4];
        result[5] = fullBytes[5];
        result[6] = 0x2e;
        result[7] = 0x2e;
        result[8] = fullBytes[38];
        result[9] = fullBytes[39];
        result[10] = fullBytes[40];
        result[11] = fullBytes[41];
        return string(result);
    }

    function _digitCount(uint256 value) private pure returns (uint256) {
        uint256 count = 0;
        uint256 t = value;
        do {
            count++;
            t /= 10;
        } while (t != 0);
        return count;
    }
}
