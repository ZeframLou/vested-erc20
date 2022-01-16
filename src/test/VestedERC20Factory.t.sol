// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.11;

import {DSTest} from "ds-test/test.sol";

import {VestedERC20} from "../VestedERC20.sol";
import {VestedERC20Factory} from "../VestedERC20Factory.sol";

contract VestedERC20FactoryTest is DSTest {
    VestedERC20Factory factory;

    function setUp() public {
        VestedERC20 implementation = new VestedERC20();
        factory = new VestedERC20Factory(implementation);
    }

    /// -------------------------------------------------------------------
    /// Gas benchmarking
    /// -------------------------------------------------------------------

    function testGas_createVestedERC20(
        bytes32 name,
        bytes32 symbol,
        uint8 decimals,
        address underlying,
        uint56 startTimestamp
    ) public {
        factory.createVestedERC20(
            name,
            symbol,
            decimals,
            underlying,
            startTimestamp,
            startTimestamp + 365 days
        );
    }

    /// -------------------------------------------------------------------
    /// Correctness tests
    /// -------------------------------------------------------------------

    function testCorrectness_createVestedERC20(
        bytes32 name,
        bytes32 symbol,
        uint8 decimals,
        address underlying,
        uint56 startTimestamp
    ) public {
        VestedERC20 vestedToken = factory.createVestedERC20(
            name,
            symbol,
            decimals,
            underlying,
            startTimestamp,
            startTimestamp + 365 days
        );

        // assertEq(name, vestedToken.name());
        assertEq(vestedToken.decimals(), decimals);
        assertEq(vestedToken.underlying(), underlying);
        assertEq(
            uint256(vestedToken.startTimestamp()),
            uint256(startTimestamp)
        );
        assertEq(
            uint256(vestedToken.endTimestamp()),
            uint256(startTimestamp + 365 days)
        );
    }
}
