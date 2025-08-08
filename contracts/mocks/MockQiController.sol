// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockQiController {
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    uint256 public rewardAmount;

    constructor(address _rewardToken) {
        rewardToken = IERC20(_rewardToken);
    }

    function setReward(uint256 amount) external {
        rewardAmount = amount;
    }

    function claimReward(uint8, address holder, address[] calldata) external {
        rewardToken.safeTransfer(holder, rewardAmount);
        rewardAmount = 0;
    }
}

