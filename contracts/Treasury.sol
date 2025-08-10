// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Timelocked treasury for protocol funds
/// @notice Stores assets withdrawn from the bootloader and releases them after a delay
contract Treasury is Ownable {
    using SafeERC20 for IERC20;

    struct Withdrawal {
        address token;
        address to;
        uint256 amount;
        uint256 executeAfter;
        uint256 reasonCode;
        bool executed;
    }

    uint256 public immutable delay;
    mapping(bytes32 => Withdrawal) public withdrawals;

    event WithdrawalQueued(
        bytes32 indexed id,
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 executeAfter,
        uint256 reasonCode
    );

    event WithdrawalExecuted(
        bytes32 indexed id,
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 reasonCode
    );

    constructor(uint256 _delay) {
        delay = _delay;
    }

    /// @notice Queue a withdrawal that can be executed after the delay
    function queueWithdrawal(
        address token,
        address to,
        uint256 amount,
        uint256 reasonCode
    ) external onlyOwner returns (bytes32 id) {
        require(to != address(0), "invalid to");
        require(amount > 0, "invalid amount");

        id = keccak256(abi.encode(token, to, amount, block.timestamp, reasonCode));
        Withdrawal storage w = withdrawals[id];
        require(w.executeAfter == 0, "exists");

        w.token = token;
        w.to = to;
        w.amount = amount;
        w.executeAfter = block.timestamp + delay;
        w.reasonCode = reasonCode;

        emit WithdrawalQueued(id, token, to, amount, w.executeAfter, reasonCode);
    }

    /// @notice Execute a previously queued withdrawal after the delay
    function executeWithdrawal(bytes32 id) external onlyOwner {
        Withdrawal storage w = withdrawals[id];
        require(w.executeAfter != 0, "not queued");
        require(!w.executed, "executed");
        require(block.timestamp >= w.executeAfter, "too early");

        w.executed = true;

        if (w.token == address(0)) {
            (bool success, ) = w.to.call{value: w.amount}("");
            require(success, "AVAX transfer failed");
        } else {
            IERC20(w.token).safeTransfer(w.to, w.amount);
        }

        emit WithdrawalExecuted(id, w.token, w.to, w.amount, w.reasonCode);
        delete withdrawals[id];
    }

    receive() external payable {}
}

