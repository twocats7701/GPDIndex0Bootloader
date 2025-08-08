// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MockERC20.sol";

contract MockUniswapRouter {
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    MockERC20 public immutable underlying;

    constructor(address _rewardToken, address _underlying) {
        rewardToken = IERC20(_rewardToken);
        underlying = MockERC20(_underlying);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        pure
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            amounts[i] = amountIn;
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256,
        address[] calldata,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        rewardToken.safeTransferFrom(msg.sender, address(this), amountIn);
        underlying.mint(to, amountIn);
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn;
    }
}

