// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Simple mock for PASS OTC service
contract MockOtcPass {
    using SafeERC20 for IERC20;

    uint256 public rate = 1e18; // 1:1 rate

    function setRate(uint256 newRate) external {
        rate = newRate;
    }

    function quote(address, address, uint256 amountIn) external view returns (uint256) {
        return (amountIn * rate) / 1e18;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address to
    ) external returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        amountOut = (amountIn * rate) / 1e18;
        require(amountOut >= minAmountOut, "slippage");
        IERC20(tokenOut).safeTransfer(to, amountOut);
    }
}

