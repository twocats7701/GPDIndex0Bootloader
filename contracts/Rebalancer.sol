// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./GPDYieldVault0.sol"; // for IYieldStrategy

interface IVaultLike {
    function asset() external view returns (address);
}

contract Rebalancer {
    using SafeERC20 for IERC20;

    /// @notice Rebalance funds from one strategy to another if target APR is higher
    /// @param fromStrategy Address of the strategy to withdraw from
    /// @param toStrategy Address of the strategy to deposit into
    /// @param amount Amount of underlying asset to move
    /// @param fromApr APR of the source strategy (bps or any units)
    /// @param toApr APR of the target strategy
    function rebalance(
        address fromStrategy,
        address toStrategy,
        uint256 amount,
        uint256 fromApr,
        uint256 toApr
    ) external {
        require(toApr > fromApr, "APR not improved");
        require(fromStrategy != address(0) && toStrategy != address(0), "invalid strategy");

        // Withdraw from current strategy
        IYieldStrategy(fromStrategy).withdraw(amount);

        // Approve and deposit into new strategy
        address assetAddr = IVaultLike(address(this)).asset();
        IERC20 assetToken = IERC20(assetAddr);

        assetToken.safeApprove(fromStrategy, 0);
        assetToken.safeApprove(toStrategy, 0);
        assetToken.safeApprove(toStrategy, type(uint256).max);

        IYieldStrategy(toStrategy).deposit(amount);
    }
}
