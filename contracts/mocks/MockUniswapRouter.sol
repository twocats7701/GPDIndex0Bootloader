// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MockERC20.sol";

contract MockUniswapRouter {
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    MockERC20 public immutable underlying;

    uint256 public quoteRate = 1e18; // rate used for getAmountsOut
    uint256 public swapRate = 1e18;  // rate used for swap

    constructor(address _rewardToken, address _underlying) {
        rewardToken = IERC20(_rewardToken);
        underlying = MockERC20(_underlying);
    }

    function setQuoteRate(uint256 rate) external {
        quoteRate = rate;
    }

    function setSwapRate(uint256 rate) external {
        swapRate = rate;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 1; i < path.length; i++) {
            amounts[i] = (amounts[i - 1] * quoteRate) / 1e18;
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        rewardToken.safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 out = (amountIn * swapRate) / 1e18;
        require(out >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        underlying.mint(to, out);
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 1; i < path.length; i++) {
            amounts[i] = out;
        }
    }
}

