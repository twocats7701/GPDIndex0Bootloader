// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFlashLoanSimpleReceiver {
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params) external returns (bool);
}

contract MockAaveV3Pool {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlying;
    uint256 public premiumBps = 9; // 0.09%

    mapping(address => uint256) public balance;
    mapping(address => uint256) public debt;

    constructor(address _underlying) {
        underlying = IERC20(_underlying);
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
        require(asset == address(underlying), "asset");
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        balance[onBehalfOf] += amount;
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        require(asset == address(underlying), "asset");
        require(balance[msg.sender] >= amount, "bal");
        balance[msg.sender] -= amount;
        underlying.safeTransfer(to, amount);
        return amount;
    }

    function borrow(address asset, uint256 amount, uint256, uint16, address onBehalfOf) external {
        require(asset == address(underlying), "asset");
        debt[onBehalfOf] += amount;
        underlying.safeTransfer(msg.sender, amount);
    }

    function flashLoanSimple(address receiver, address asset, uint256 amount, bytes calldata params, uint16) external {
        require(asset == address(underlying), "asset");
        uint256 premium = (amount * premiumBps) / 10_000;
        underlying.safeTransfer(receiver, amount);
        require(IFlashLoanSimpleReceiver(receiver).executeOperation(asset, amount, premium, msg.sender, params), "flash failed");
        require(underlying.balanceOf(address(this)) >= amount + premium, "not repaid");
    }
}

