// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MockERC20.sol";

contract MockAVAXRouter {
    using SafeERC20 for IERC20;

    address public immutable wavax;
    MockERC20 public immutable token;

    uint256 public quoteRate = 1e18; // token per AVAX for quoting
    uint256 public swapRate = 1e18;  // token per AVAX for actual swap

    constructor(address _wavax, address _token) {
        wavax = _wavax;
        token = MockERC20(_token);
    }

    function setQuoteRate(uint256 rate) external {
        quoteRate = rate;
    }

    function setSwapRate(uint256 rate) external {
        swapRate = rate;
    }

    function WAVAX() external view returns (address) {
        return wavax;
    }

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts) {
        require(path.length == 2 && path[0] == wavax && path[1] == address(token), "path");
        amounts = new uint[](2);
        amounts[0] = amountIn;
        amounts[1] = amountIn * quoteRate / 1e18;
    }

    function swapExactAVAXForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint /*deadline*/
    ) external payable returns (uint[] memory amounts) {
        require(path.length == 2 && path[0] == wavax && path[1] == address(token), "path");
        uint256 out = msg.value * swapRate / 1e18;
        require(out >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        token.mint(to, out);
        amounts = new uint[](2);
        amounts[0] = msg.value;
        amounts[1] = out;
    }

    function addLiquidityAVAX(
        address tokenAddr,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountAVAXMin,
        address /*to*/,
        uint /*deadline*/
    ) external payable returns (uint amountToken, uint amountAVAX, uint liquidity) {
        require(tokenAddr == address(token), "token");
        require(amountTokenDesired >= amountTokenMin, "TOKEN_SLIPPAGE");
        require(msg.value >= amountAVAXMin, "AVAX_SLIPPAGE");
        IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), amountTokenDesired);
        amountToken = amountTokenDesired;
        amountAVAX = msg.value;
        liquidity = amountAVAX;
    }
}

