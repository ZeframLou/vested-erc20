// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.11;

import {ERC20 as SolmateERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import {ERC20} from "./lib/ERC20.sol";

contract VestedERC20 is ERC20 {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeTransferLib for SolmateERC20;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error Error_Wrap_VestOver();
    error Error_Wrap_AmountTooLarge();

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    mapping(address => uint256) public claimedUnderlyingAmount;

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    function underlying() public pure returns (address _underlying) {
        uint256 offset = _getImmutableVariablesOffset();
        assembly {
            _underlying := shr(0x60, calldataload(add(offset, 0x41)))
        }
    }

    function startTimestamp() public pure returns (uint64 _startTimestamp) {
        uint256 offset = _getImmutableVariablesOffset();
        assembly {
            _startTimestamp := shr(0xc0, calldataload(add(offset, 0x55)))
        }
    }

    function endTimestamp() public pure returns (uint64 _endTimestamp) {
        uint256 offset = _getImmutableVariablesOffset();
        assembly {
            _endTimestamp := shr(0xc0, calldataload(add(offset, 0x5d)))
        }
    }

    /// -----------------------------------------------------------------------
    /// User actions
    /// -----------------------------------------------------------------------

    function wrap(uint256 underlyingAmount, address recipient)
        external
        returns (uint256 wrappedTokenAmount)
    {
        /// -------------------------------------------------------------------
        /// Validation
        /// -------------------------------------------------------------------

        uint256 _startTimestamp = startTimestamp();
        uint256 _endTimestamp = endTimestamp();
        if (block.timestamp >= _endTimestamp) {
            revert Error_Wrap_VestOver();
        }
        if (
            underlyingAmount >=
            type(uint256).max / (_endTimestamp - _startTimestamp)
        ) {
            revert Error_Wrap_AmountTooLarge();
        }

        /// -------------------------------------------------------------------
        /// State updates
        /// -------------------------------------------------------------------

        if (block.timestamp >= _startTimestamp) {
            // vest already started
            // wrappedTokenAmount * (endTimestamp() - block.timestamp) / (endTimestamp() - startTimestamp()) == underlyingAmount
            // thus, wrappedTokenAmount = underlyingAmount * (endTimestamp() - startTimestamp()) / (endTimestamp() - block.timestamp)
            wrappedTokenAmount =
                (underlyingAmount * (_endTimestamp - _startTimestamp)) /
                (_endTimestamp - block.timestamp);

            // pretend we have claimed the vested underlying amount
            claimedUnderlyingAmount[recipient] +=
                wrappedTokenAmount -
                underlyingAmount;
        } else {
            // vest hasn't started yet
            wrappedTokenAmount = underlyingAmount;
        }
        // mint wrapped tokens
        _mint(recipient, wrappedTokenAmount);

        /// -------------------------------------------------------------------
        /// Effects
        /// -------------------------------------------------------------------

        SolmateERC20 underlyingToken = SolmateERC20(underlying());
        underlyingToken.safeTransferFrom(
            msg.sender,
            address(this),
            underlyingAmount
        );
    }

    function redeem(address recipient) external {
        /// -------------------------------------------------------------------
        /// State updates
        /// -------------------------------------------------------------------

        uint256 _claimedUnderlyingAmount = claimedUnderlyingAmount[msg.sender];
        uint256 redeemableAmount = _getRedeemableAmount(
            msg.sender,
            _claimedUnderlyingAmount
        );
        claimedUnderlyingAmount[msg.sender] =
            _claimedUnderlyingAmount +
            redeemableAmount;

        /// -------------------------------------------------------------------
        /// Effects
        /// -------------------------------------------------------------------

        if (redeemableAmount > 0) {
            SolmateERC20 underlyingToken = SolmateERC20(underlying());
            underlyingToken.safeTransfer(recipient, redeemableAmount);
        }
    }

    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        uint256 senderBalance = balanceOf[msg.sender];
        uint256 senderClaimedUnderlyingAmount = claimedUnderlyingAmount[
            msg.sender
        ];
        uint256 claimedUnderlyingAmountToTransfer = (senderClaimedUnderlyingAmount *
                amount) / senderBalance;

        balanceOf[msg.sender] = senderBalance - amount;
        claimedUnderlyingAmount[msg.sender] =
            senderClaimedUnderlyingAmount -
            claimedUnderlyingAmountToTransfer;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
            claimedUnderlyingAmount[to] += claimedUnderlyingAmountToTransfer;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max)
            allowance[from][msg.sender] = allowed - amount;

        uint256 fromBalance = balanceOf[from];
        uint256 fromClaimedUnderlyingAmount = claimedUnderlyingAmount[from];
        uint256 claimedUnderlyingAmountToTransfer = (fromClaimedUnderlyingAmount *
                amount) / fromBalance;

        balanceOf[from] = fromBalance - amount;
        claimedUnderlyingAmount[from] =
            fromClaimedUnderlyingAmount -
            claimedUnderlyingAmountToTransfer;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
            claimedUnderlyingAmount[to] += claimedUnderlyingAmountToTransfer;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    function getRedeemableAmount(address holder)
        external
        view
        returns (uint256)
    {
        return _getRedeemableAmount(holder, claimedUnderlyingAmount[holder]);
    }

    function _getRedeemableAmount(
        address holder,
        uint256 holderClaimedUnderlyingAmount
    ) internal view returns (uint256) {
        uint256 _startTimestamp = startTimestamp();
        uint256 _endTimestamp = endTimestamp();
        if (block.timestamp <= _startTimestamp) {
            // vest hasn't started yet, nothing is vested
            return 0;
        } else if (block.timestamp >= _endTimestamp) {
            // vest is over, everything is vested
            return balanceOf[holder] - holderClaimedUnderlyingAmount;
        } else {
            // middle of vest, compute linear vesting
            return
                (balanceOf[holder] * (block.timestamp - _startTimestamp)) /
                (_endTimestamp - _startTimestamp) -
                holderClaimedUnderlyingAmount;
        }
    }
}
