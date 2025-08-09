// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev Minimal mock of GMX reward tracker used for testing.
 * It allows staking of GMX and esGMX tokens and simulates reward
 * accrual that can be claimed by stakers.
 */
contract MockGmxRewardTracker {
    using SafeERC20 for IERC20;

    IERC20 public immutable gmx;
    IERC20 public immutable esGmx;

    mapping(address => uint256) public staked;
    mapping(address => uint256) public rewards;

    constructor(address _gmx, address _esGmx) {
        gmx = IERC20(_gmx);
        esGmx = IERC20(_esGmx);
    }

    function stake(
        address fundingAccount,
        address account,
        address depositToken,
        uint256 amount
    ) external {
        require(depositToken == address(gmx) || depositToken == address(esGmx), "bad token");
        IERC20(depositToken).safeTransferFrom(fundingAccount, address(this), amount);
        staked[account] += amount;
    }

    function unstake(
        address account,
        address depositToken,
        uint256 amount,
        address receiver
    ) external {
        require(staked[account] >= amount, "too much");
        staked[account] -= amount;
        IERC20(depositToken).safeTransfer(receiver, amount);
    }

    function claim(address receiver) external returns (uint256) {
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        if (reward > 0) {
            esGmx.safeTransfer(receiver, reward);
        }
        return reward;
    }

    function claimable(address account) external view returns (uint256) {
        return rewards[account];
    }

    /// @dev testing helper to allocate rewards to an account
    function addReward(address account, uint256 amount) external {
        esGmx.safeTransferFrom(msg.sender, address(this), amount);
        rewards[account] += amount;
    }
}

