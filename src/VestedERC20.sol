// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.11;

import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {ERC20} from "./lib/ERC20.sol";
import {FullMath} from "./lib/FullMath.sol";

/// @title VestedERC20
/// @author zefram.eth
/// @notice An ERC20 wrapper token that linearly vests an underlying token to
/// its holders
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

    /// @notice The amount of underlying tokens claimed by a token holder
    mapping(address => uint256) public claimedUnderlyingAmount;

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice The token that is vested
    /// @return _underlying The address of the underlying token
    function underlying() public pure returns (address _underlying) {
        return _getArgAddress(0x41);
    }

    /// @notice The Unix timestamp (in seconds) of the start of the vest
    /// @return _startTimestamp The vest start timestamp
    function startTimestamp() public pure returns (uint64 _startTimestamp) {
        return _getArgUint64(0x55);
    }

    /// @notice The Unix timestamp (in seconds) of the end of the vest
    /// @return _endTimestamp The vest end timestamp
    function endTimestamp() public pure returns (uint64 _endTimestamp) {
        return _getArgUint64(0x5d);
    }

    /// -----------------------------------------------------------------------
    /// User actions
    /// -----------------------------------------------------------------------

    /// @notice Mints wrapped tokens using underlying tokens. Can only be called before the vest is over.
    /// @param underlyingAmount The amount of underlying tokens to wrap
    /// @param recipient The address that will receive the minted wrapped tokens
    /// @return wrappedTokenAmount The amount of wrapped tokens minted
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

    /// @notice Allows a holder of the wrapped token to redeem the vested tokens
    /// @param recipient The address that will receive the vested tokens
    /// @return redeemedAmount The amount of vested tokens redeemed
    function redeem(address recipient)
        external
        returns (uint256 redeemedAmount)
    {
        /// -------------------------------------------------------------------
        /// State updates
        /// -------------------------------------------------------------------

        uint256 _claimedUnderlyingAmount = claimedUnderlyingAmount[msg.sender];
        redeemedAmount = _getRedeemableAmount(
            msg.sender,
            _claimedUnderlyingAmount
        );
        claimedUnderlyingAmount[msg.sender] =
            _claimedUnderlyingAmount +
            redeemedAmount;

        /// -------------------------------------------------------------------
        /// Effects
        /// -------------------------------------------------------------------

        if (redeemedAmount > 0) {
            SolmateERC20 underlyingToken = SolmateERC20(underlying());
            underlyingToken.safeTransfer(recipient, redeemedAmount);
        }
    }

    /// @notice The ERC20 transfer function
    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        uint256 senderBalance = balanceOf[msg.sender];
        uint256 senderClaimedUnderlyingAmount = claimedUnderlyingAmount[
            msg.sender
        ];

        balanceOf[msg.sender] = senderBalance - amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        uint256 claimedUnderlyingAmountToTransfer = FullMath.mulDiv(
            senderClaimedUnderlyingAmount,
            amount,
            senderBalance
        );

        if (claimedUnderlyingAmountToTransfer > 0) {
            claimedUnderlyingAmount[msg.sender] =
                senderClaimedUnderlyingAmount -
                claimedUnderlyingAmountToTransfer;
            unchecked {
                claimedUnderlyingAmount[
                    to
                ] += claimedUnderlyingAmountToTransfer;
            }
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    /// @notice The ERC20 transferFrom function
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

        balanceOf[from] = fromBalance - amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        uint256 claimedUnderlyingAmountToTransfer = FullMath.mulDiv(
            fromClaimedUnderlyingAmount,
            amount,
            fromBalance
        );
        if (claimedUnderlyingAmountToTransfer > 0) {
            claimedUnderlyingAmount[from] =
                fromClaimedUnderlyingAmount -
                claimedUnderlyingAmountToTransfer;
            unchecked {
                claimedUnderlyingAmount[
                    to
                ] += claimedUnderlyingAmountToTransfer;
            }
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /// -----------------------------------------------------------------------
    /// Getters
    /// -----------------------------------------------------------------------

    /// @notice Computes the amount of vested tokens redeemable by an account
    /// @param holder The wrapped token holder to query
    /// @return The amount of vested tokens redeemable
    function getRedeemableAmount(address holder)
        external
        view
        returns (uint256)
    {
        return _getRedeemableAmount(holder, claimedUnderlyingAmount[holder]);
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

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
