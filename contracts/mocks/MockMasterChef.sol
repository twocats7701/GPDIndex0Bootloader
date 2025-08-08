// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockMasterChef {
    using SafeERC20 for IERC20;

    IERC20 public lpToken;
    IERC20 public rewardToken;
    uint256 public staked;
    uint256 public pending;

    constructor(address _lpToken, address _rewardToken) {
        lpToken = IERC20(_lpToken);
        rewardToken = IERC20(_rewardToken);
    }

    function deposit(uint256, uint256 amount) external {
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        staked += amount;
    }

    function withdraw(uint256, uint256 amount) external {
        if (amount > 0) {
            lpToken.safeTransfer(msg.sender, amount);
            staked -= amount;
        } else {
            uint256 toSend = pending;
            pending = 0;
            rewardToken.safeTransfer(msg.sender, toSend);
        }
    }

    function setPending(uint256 amount) external {
        pending = amount;
    }

    function userInfo(uint256, address) external view returns (uint256 amount, uint256 rewardDebt) {
        amount = staked;
        rewardDebt = 0;
    }

    function pendingReward(uint256, address) external view returns (uint256) {
        return pending;
    }
}
