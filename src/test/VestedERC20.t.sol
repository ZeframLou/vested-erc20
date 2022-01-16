// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.11;

import {DSTest} from "ds-test/test.sol";

import {VM} from "./utils/VM.sol";
import {VestedERC20} from "../VestedERC20.sol";
import {TestERC20} from "./mocks/TestERC20.sol";
import {VestedERC20Factory} from "../VestedERC20Factory.sol";

contract VestedERC20Test is DSTest {
    VM constant vm = VM(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address constant tester = address(69);
    address constant burn = address(0xdead);

    VestedERC20Factory factory;
    TestERC20 underlying;
    VestedERC20 wrappedToken;
    uint256 startTimestamp;

    function setUp() public {
        VestedERC20 implementation = new VestedERC20();
        factory = new VestedERC20Factory(implementation);
        underlying = new TestERC20();
        wrappedToken = factory.createVestedERC20(
            bytes32(0),
            bytes32(0),
            18,
            address(underlying),
            uint64(block.timestamp + 1 days),
            uint64(block.timestamp + 101 days)
        );
        startTimestamp = block.timestamp + 1 days;

        underlying.mint(address(this), 100 ether);
        underlying.approve(address(wrappedToken), type(uint256).max);

        wrappedToken.wrap(1 ether, address(this));
    }

    /// -------------------------------------------------------------------
    /// Gas benchmarking
    /// -------------------------------------------------------------------

    function testGas_wrap() public {
        wrappedToken.wrap(0.1 ether, address(this));
    }

    function testGas_redeem() public {
        vm.warp(startTimestamp + 10 days);
        wrappedToken.redeem(address(this));
    }

    function testGas_transfer() public {
        wrappedToken.transfer(tester, 0.1 ether);
    }

    /// -------------------------------------------------------------------
    /// Correctness tests
    /// -------------------------------------------------------------------

    function testCorrectness_wrapAndClaim_duringVest(uint224 underlyingAmount)
        public
    {
        vm.warp(startTimestamp + 10 days);

        // mint underlying and wrap
        // tester receives the wrapped tokens
        uint256 beforeUnderlyingTokenBalanceTester = underlying.balanceOf(
            tester
        );
        uint256 beforeUnderlyingTokenBalanceWrappedToken = underlying.balanceOf(
            address(wrappedToken)
        );
        uint256 beforeWrappedTokenBalance = wrappedToken.balanceOf(tester);
        underlying.mint(address(this), underlyingAmount);
        uint256 returnedWrappedTokenAmount = wrappedToken.wrap(
            underlyingAmount,
            tester
        );
        uint256 actualWrappedTokenAmount = wrappedToken.balanceOf(tester) -
            beforeWrappedTokenBalance;

        // check wrapped token balances
        assertEq(returnedWrappedTokenAmount, actualWrappedTokenAmount);
        assertEq(
            returnedWrappedTokenAmount,
            _computeMintAmount(underlyingAmount)
        );

        // check underlying token balances
        assertEq(
            underlying.balanceOf(tester),
            beforeUnderlyingTokenBalanceTester
        );
        assertEq(
            underlying.balanceOf(address(wrappedToken)),
            beforeUnderlyingTokenBalanceWrappedToken + underlyingAmount
        );

        // check that the tester can redeem 0 tokens
        vm.prank(tester);
        uint256 redeemedAmount = wrappedToken.redeem(tester);
        assertEq(redeemedAmount, 0);

        // warp
        vm.warp(startTimestamp + 40 days);

        // check that redeeming gives 1/3 of tokens
        vm.prank(tester);
        redeemedAmount = wrappedToken.redeem(tester);
        assertGe(redeemedAmount, underlyingAmount / 3);

        // check that redeeming again gives 0 tokens
        vm.prank(tester);
        redeemedAmount = wrappedToken.redeem(tester);
        assertGe(redeemedAmount, 0);
    }

    function testFail_wrap_afterVestEnd(uint224 underlyingAmount) public {
        vm.warp(startTimestamp + 102 days);

        underlying.mint(address(this), underlyingAmount);
        wrappedToken.wrap(underlyingAmount, address(this));
    }

    function testCorrectness_wrapAndClaim_beforeVestStart(
        uint224 underlyingAmount
    ) public {
        // mint and wrap
        underlying.mint(address(this), underlyingAmount);
        uint256 returnedWrappedTokenAmount = wrappedToken.wrap(
            underlyingAmount,
            address(this)
        );

        // wrapped token amount should equal underlying
        assertEq(returnedWrappedTokenAmount, underlyingAmount);

        // redeeming should give 0
        uint256 redeemedAmount = wrappedToken.redeem(address(this));
        assertEq(redeemedAmount, 0);
    }

    function testCorrectness_wrapAndClaim_transfer(uint224 underlyingAmount_)
        public
    {
        uint256 underlyingAmount = uint256(underlyingAmount_);

        // clear wrapped token balance
        wrappedToken.transfer(burn, wrappedToken.balanceOf(address(this)));

        // mint and wrap
        underlying.mint(address(this), underlyingAmount);
        uint256 wrappedTokenAmount = wrappedToken.wrap(
            underlyingAmount,
            address(this)
        );

        // go to when 10% of the vest is done
        vm.warp(startTimestamp + 10 days);

        // redeem from this
        uint256 redeemedUnderlyingAmount = wrappedToken.redeem(address(this));
        assertEq(redeemedUnderlyingAmount, (underlyingAmount * 10) / 100);

        // transfer 1/3 of wrapped tokens to tester
        wrappedToken.transfer(tester, wrappedTokenAmount / 3);

        // go to when 50% of the vest is done
        vm.warp(startTimestamp + 50 days);

        // redeem from this
        redeemedUnderlyingAmount = wrappedToken.redeem(address(this));
        assertGe(
            redeemedUnderlyingAmount,
            (underlyingAmount * 2 * 4) / (3 * 10) - 1
        );

        // redeem from tester
        vm.prank(tester);
        assertGe(
            wrappedToken.redeem(tester),
            (underlyingAmount * 1 * 4) / (3 * 10) - 1
        );
    }

    /// -------------------------------------------------------------------
    /// Internal utilities
    /// -------------------------------------------------------------------

    function _computeMintAmount(uint256 underlyingAmount)
        internal
        view
        returns (uint256 wrappedTokenAmount)
    {
        uint256 _startTimestamp = wrappedToken.startTimestamp();
        uint256 _endTimestamp = wrappedToken.endTimestamp();
        if (block.timestamp >= _startTimestamp) {
            // vest already started
            // wrappedTokenAmount * (endTimestamp() - block.timestamp) / (endTimestamp() - startTimestamp()) == underlyingAmount
            // thus, wrappedTokenAmount = underlyingAmount * (endTimestamp() - startTimestamp()) / (endTimestamp() - block.timestamp)
            wrappedTokenAmount =
                (underlyingAmount * (_endTimestamp - _startTimestamp)) /
                (_endTimestamp - block.timestamp);
        } else {
            // vest hasn't started yet
            wrappedTokenAmount = underlyingAmount;
        }
    }
}
