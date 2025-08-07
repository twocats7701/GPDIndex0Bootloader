// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockBlackholePool {
    IERC20 public immutable token;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public rewards;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insufficient");
        balances[msg.sender] -= amount;
        token.transfer(msg.sender, amount);
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function claim() external returns (uint256) {
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        token.transfer(msg.sender, reward);
        return reward;
    }

    function notifyReward(address user, uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        rewards[user] += amount;
    }
}

