// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MockERC20.sol";

contract MockPlatypusRouter {
    using SafeERC20 for IERC20;

    IERC20 public immutable tokenIn;
    MockERC20 public immutable tokenOut;

    uint256 public quoteRate = 1e18; // rate for getQuoteFromPool
    uint256 public swapRate = 1e18;  // rate for swap

    mapping(address => uint256) public coverageRatios;

    constructor(address _tokenIn, address _tokenOut) {
        tokenIn = IERC20(_tokenIn);
        tokenOut = MockERC20(_tokenOut);
    }

    function setQuoteRate(uint256 rate) external {
        quoteRate = rate;
    }

    function setSwapRate(uint256 rate) external {
        swapRate = rate;
    }

    function setCoverageRatio(address token, uint256 ratio) external {
        coverageRatios[token] = ratio;
    }

    function getQuoteFromPool(address fromToken, address toToken, uint256 amountIn) external view returns (uint256) {
        require(fromToken == address(tokenIn) && toToken == address(tokenOut), "unsupported pair");
        return (amountIn * quoteRate) / 1e18;
    }

    function getCoverageRatio(address token) external view returns (uint256) {
        return coverageRatios[token];
    }

    function swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        uint256 minAmountOut,
        address to
    ) external returns (uint256 amountOut) {
        require(fromToken == address(tokenIn) && toToken == address(tokenOut), "unsupported pair");
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        amountOut = (amountIn * swapRate) / 1e18;
        require(amountOut >= minAmountOut, "INSUFFICIENT_OUTPUT_AMOUNT");
        tokenOut.mint(to, amountOut);
    }
}

