// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./GPDYieldVault0.sol";

/**
 * @title SimpleStakingStrategy
 * @dev Simulates staking and auto-harvesting logic for GPDYieldVault0
 */

contract SimpleStakingStrategy is Ownable, ReentrancyGuard, IYieldStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public vault;

    uint256 public totalStaked;
    uint256 public simulatedYield;

    constructor(address _token) {
        token = IERC20(_token);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Not authorized");
        _;
    }

    function setVault(address _vault) external onlyOwner {
        if (vault != address(0)) {
            token.safeApprove(vault, 0);
        }
        vault = _vault;
        token.safeApprove(vault, type(uint256).max);
    }

    function _deposit(uint256 amount) internal {
        token.safeTransferFrom(msg.sender, address(this), amount);
        totalStaked += amount;
    }

    function deposit(uint256 amount) external onlyVault nonReentrant {
        _deposit(amount);
    }

    function deposit(uint256 amount, uint256 /*slippageBpsOverride*/) public onlyVault nonReentrant {
        _deposit(amount);
    }

    function _withdraw(uint256 amount) internal {
        require(amount <= totalStaked, "Insufficient balance");
        totalStaked -= amount;
        token.safeTransfer(vault, amount);
    }

    function withdraw(uint256 amount) external onlyVault nonReentrant {
        _withdraw(amount);
    }

    function withdraw(uint256 amount, uint256 /*slippageBpsOverride*/) public onlyVault nonReentrant {
        _withdraw(amount);
    }

    function totalAssets() external view returns (uint256) {
        return totalStaked + simulatedYield;
    }

    function harvest(uint256 /*slippageBpsOverride*/) external onlyVault nonReentrant returns (uint256) {
        uint256 yield = simulatedYield;
        simulatedYield = 0;
        token.safeTransfer(vault, yield);
        return yield;
    }

    // Dev tool to simulate yield growth
    function simulateYield(uint256 amount) external onlyOwner {
        simulatedYield += amount;
    }
}
