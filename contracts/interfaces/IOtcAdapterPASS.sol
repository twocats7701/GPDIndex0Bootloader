// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOtcAdapterPASS {
    function sell(address asset, uint256 amount, address receiver) external;
}
