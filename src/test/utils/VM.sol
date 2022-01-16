// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.11;

interface VM {
    function warp(uint256 x) external;

    function expectRevert(bytes calldata) external;

    function prank(address sender) external;
}
