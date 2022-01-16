// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.11;

import {ERC20} from "./lib/ERC20.sol";
import {VestedERC20} from "./VestedERC20.sol";
import {ClonesWithCallData} from "./lib/ClonesWithCallData.sol";

contract VestedERC20Factory {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using ClonesWithCallData for address;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error Error_InvalidTimeRange();

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    VestedERC20 public immutable implementation;

    constructor(VestedERC20 implementation_) {
        implementation = implementation_;
    }

    function createVestedERC20(
        bytes32 name,
        bytes32 symbol,
        uint8 decimals,
        address underlying,
        uint64 startTimestamp,
        uint64 endTimestamp
    ) external returns (VestedERC20) {
        if (endTimestamp <= startTimestamp) {
            revert Error_InvalidTimeRange();
        }

        bytes memory ptr = new bytes(101);
        assembly {
            mstore(add(ptr, 0x20), name)
            mstore(add(ptr, 0x40), symbol)
            mstore8(add(ptr, 0x60), decimals)
            mstore(add(ptr, 0x61), shl(0x60, underlying))
            mstore(add(ptr, 0x75), shl(0xc0, startTimestamp))
            mstore(add(ptr, 0x7d), shl(0xc0, endTimestamp))
        }
        return
            VestedERC20(
                address(implementation).cloneWithCallDataProvision(ptr)
            );
    }
}
