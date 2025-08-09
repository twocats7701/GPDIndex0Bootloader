// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IAavePool.sol";

contract FlashLoanExecutor is Ownable {
    using SafeERC20 for IERC20;

    bool public shouldFail;

    function setShouldFail(bool value) external onlyOwner {
        shouldFail = value;
    }

    function execute(address pool, address asset, uint256 amount, uint256 premium, address onBehalfOf) external {
        require(!shouldFail, "exec fail");
        IERC20(asset).safeApprove(pool, 0);
        IERC20(asset).safeApprove(pool, amount);
        IAavePool(pool).supply(asset, amount, onBehalfOf, 0);
        IAavePool(pool).borrow(asset, amount + premium, 2, 0, onBehalfOf);
        IERC20(asset).safeTransfer(pool, amount + premium);
    }
}

