// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title KeeperSlasher
 * @notice Manages keeper registration and banning.
 */
contract KeeperSlasher {
    address public owner;
    mapping(address => bool) public keepers;
    mapping(address => bool) public banned;

    event KeeperBanned(address indexed keeper);
    event KeeperUnbanned(address indexed keeper);
    event KeeperRegistered(address indexed keeper);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function registerKeeper(address keeper) external onlyOwner {
        keepers[keeper] = true;
        emit KeeperRegistered(keeper);
    }

    function banKeeper(address keeper) external onlyOwner {
        banned[keeper] = true;
        emit KeeperBanned(keeper);
    }

    function unbanKeeper(address keeper) external onlyOwner {
        banned[keeper] = false;
        emit KeeperUnbanned(keeper);
    }

    function isAllowed(address keeper) external view returns (bool) {
        return keepers[keeper] && !banned[keeper];
    }
}

