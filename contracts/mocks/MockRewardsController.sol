// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockRewardsController {
    using SafeERC20 for IERC20;

    IERC20 public immutable reward;

    constructor(address _reward) {
        reward = IERC20(_reward);
    }

    function claimRewards(address[] calldata, uint256, address to, address) external returns (uint256) {
        uint256 amount = reward.balanceOf(address(this));
        if (amount > 0) {
            reward.safeTransfer(to, amount);
        }
        return amount;
    }
}

