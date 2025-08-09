// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./GPDYieldVault0.sol";

interface IRewardTracker {
    function stake(address fundingAccount, address account, address depositToken, uint256 amount) external;
    function unstake(address account, address depositToken, uint256 amount, address receiver) external;
    function claim(address receiver) external returns (uint256);
    function claimable(address account) external view returns (uint256);
}

/**
 * @title GmxStakingStrategy
 * @dev Stakes GMX tokens into GMX staking contracts and compounds rewards.
 */
contract GmxStakingStrategy is Ownable, ReentrancyGuard, IYieldStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable gmx;
    IERC20 public immutable esGmx;
    IRewardTracker public immutable stakedGmxTracker;

    address public vault;
    uint256 public totalStaked;

    constructor(address _gmx, address _esGmx, address _stakedGmxTracker) {
        gmx = IERC20(_gmx);
        esGmx = IERC20(_esGmx);
        stakedGmxTracker = IRewardTracker(_stakedGmxTracker);

        gmx.safeApprove(_stakedGmxTracker, type(uint256).max);
        esGmx.safeApprove(_stakedGmxTracker, type(uint256).max);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Not authorized");
        _;
    }

    function setVault(address _vault) external onlyOwner {
        if (vault != address(0)) {
            gmx.safeApprove(vault, 0);
            esGmx.safeApprove(vault, 0);
        }
        vault = _vault;
        gmx.safeApprove(vault, type(uint256).max);
        esGmx.safeApprove(vault, type(uint256).max);
    }

    function _deposit(uint256 amount) internal {
        gmx.safeTransferFrom(msg.sender, address(this), amount);
        stakedGmxTracker.stake(address(this), address(this), address(gmx), amount);
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
        stakedGmxTracker.unstake(address(this), address(gmx), amount, address(this));
        totalStaked -= amount;
        gmx.safeTransfer(vault, amount);
    }

    function withdraw(uint256 amount) external onlyVault nonReentrant {
        _withdraw(amount);
    }

    function withdraw(uint256 amount, uint256 /*slippageBpsOverride*/) public onlyVault nonReentrant {
        _withdraw(amount);
    }

    function totalAssets() external view returns (uint256) {
        return totalStaked + stakedGmxTracker.claimable(address(this));
    }

    function harvest(uint256 /*slippageBpsOverride*/) external onlyVault nonReentrant returns (uint256) {
        uint256 rewards = stakedGmxTracker.claim(address(this));
        if (rewards > 0) {
            esGmx.safeTransfer(vault, rewards);
        }
        return rewards;
    }
}

