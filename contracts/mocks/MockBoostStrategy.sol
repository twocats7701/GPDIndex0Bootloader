// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../GPDYieldVault0.sol"; // IYieldStrategy

/**
 * @dev Simple strategy used for testing GPDBoostVault. It stakes an underlying
 * token and allows the owner to simulate reward token accrual which is harvested
 * back to the vault.
 */
contract MockBoostStrategy is Ownable, IYieldStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlying;
    IERC20 public immutable rewardToken;
    address public vault;

    uint256 public totalStaked;
    uint256 public pendingReward;
    uint256 public harvestCalls;

    constructor(address _underlying, address _rewardToken) {
        underlying = IERC20(_underlying);
        rewardToken = IERC20(_rewardToken);
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
        underlying.safeApprove(_vault, type(uint256).max);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Not vault");
        _;
    }

    function _deposit(uint256 amount) internal {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        totalStaked += amount;
    }

    function deposit(uint256 amount) external onlyVault {
        _deposit(amount);
    }

    function deposit(uint256 amount, uint256 /*slippageBpsOverride*/) public onlyVault {
        _deposit(amount);
    }

    function _withdraw(uint256 amount) internal {
        require(amount <= totalStaked, "too much");
        totalStaked -= amount;
        underlying.safeTransfer(vault, amount);
    }

    function withdraw(uint256 amount) external onlyVault {
        _withdraw(amount);
    }

    function withdraw(uint256 amount, uint256 /*slippageBpsOverride*/) public onlyVault {
        _withdraw(amount);
    }

    function totalAssets() external view returns (uint256) {
        return totalStaked;
    }

    function harvest(uint256 /*slippageBpsOverride*/ ) external onlyVault returns (uint256) {
        harvestCalls++;
        uint256 reward = pendingReward;
        pendingReward = 0;
        rewardToken.safeTransfer(vault, reward);
        return reward;
    }

    // testing helper
    function simulateReward(uint256 amount) external onlyOwner {
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        pendingReward += amount;
    }
}

