// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockFloorOracle {
    bytes public lastMessage;

    function publishFloorIntel(bytes calldata data) external {
        lastMessage = data;
    }
}
