// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockRouter {
    uint256 public quoteRate = 1e18; // price used for getAmountsOut
    uint256 public swapRate = 1e18;  // price used during swap

    function setQuoteRate(uint256 rate) external {
        quoteRate = rate;
    }

    function setSwapRate(uint256 rate) external {
        swapRate = rate;
    }

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts) {
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[1] = amountIn * quoteRate / 1e18;
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        uint256 out = amountIn * swapRate / 1e18;
        require(out >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[1] = out;
    }
}
