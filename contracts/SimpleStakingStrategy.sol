// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SimpleStakingStrategy
 * @dev Simulates staking and auto-harvesting logic for GPDYieldVault0
 */
contract SimpleStakingStrategy is Ownable {
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
        vault = _vault;
        token.approve(vault, type(uint256).max);
    }

    function deposit(uint256 amount) external onlyVault {
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        totalStaked += amount;
    }

    function withdraw(uint256 amount) external onlyVault {
        require(amount <= totalStaked, "Insufficient balance");
        totalStaked -= amount;
        require(token.transfer(vault, amount), "Withdraw failed");
    }

    function totalAssets() external view returns (uint256) {
        return totalStaked + simulatedYield;
    }

    function harvest() external onlyVault returns (uint256) {
        uint256 yield = simulatedYield;
        simulatedYield = 0;
        require(token.transfer(vault, yield), "Harvest failed");
        return yield;
    }

    // Dev tool to simulate yield growth
    function simulateYield(uint256 amount) external onlyOwner {
        simulatedYield += amount;
    }
}
