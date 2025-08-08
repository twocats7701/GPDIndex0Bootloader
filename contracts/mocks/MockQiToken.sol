// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockQiToken {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlying;
    uint256 public exchangeRate = 1e18;
    mapping(address => uint256) public balances;

    constructor(address _underlying) {
        underlying = IERC20(_underlying);
    }

    function mint(uint256 amount) external returns (uint256) {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        return 0;
    }

    function redeemUnderlying(uint256 amount) external returns (uint256) {
        require(balances[msg.sender] >= amount, "insufficient");
        balances[msg.sender] -= amount;
        underlying.safeTransfer(msg.sender, amount);
        return 0;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return balances[owner];
    }

    function exchangeRateStored() external view returns (uint256) {
        return exchangeRate;
    }

    function setExchangeRate(uint256 rate) external {
        exchangeRate = rate;
    }
}

