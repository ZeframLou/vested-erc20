// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.11;

import {ERC20} from "./lib/ERC20.sol";
import {VestedERC20} from "./VestedERC20.sol";
import {ClonesWithCallData} from "./lib/ClonesWithCallData.sol";

/// @title VestedERC20Factory
/// @author zefram.eth
/// @notice Factory for deploying VestedERC20 contracts cheaply
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

    /// @notice The VestedERC20 used as the template for all clones created
    VestedERC20 public immutable implementation;

    constructor(VestedERC20 implementation_) {
        implementation = implementation_;
    }

    /// @notice Creates a VestedERC20 contract
    /// @dev Uses a modified minimal proxy contract that stores immutable parameters in code and
    /// passes them in through calldata. See ClonesWithCallData.
    /// @param name The name of the VestedERC20 token
    /// @param symbol The symbol of the VestedERC20 token
    /// @param decimals The number of decimals used by the VestedERC20 token
    /// @param underlying The ERC20 token that is vested
    /// @param startTimestamp The start time of the vest, Unix timestamp in seconds
    /// @param endTimestamp The end time of the vest, must be greater than startTimestamp, Unix timestamp in seconds
    /// @return The created VestedERC20 contract
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
