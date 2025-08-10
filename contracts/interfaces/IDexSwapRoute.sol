// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDexSwapRoute {
    function getBestQuote(address[] calldata path, uint256 amountIn) external view returns (uint256 amountOut);
    function swap(address[] calldata path, uint256 amountIn, uint256 minAmountOut, address to) external returns (uint256 amountOut);
}
