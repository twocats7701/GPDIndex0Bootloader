// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IPASSOtc {
    function quote(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut);
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address to) external returns (uint256 amountOut);
}

/// @title OtcAdapterPASS
/// @notice Adapter for PASS OTC swaps with role-based access control
contract OtcAdapterPASS is Ownable {
    using SafeERC20 for IERC20;

    IPASSOtc public pass;

    mapping(address => bool) public routers;
    mapping(address => bool) public strategies;

    event RouterSet(address indexed router, bool allowed);
    event StrategySet(address indexed strategy, bool allowed);
    event OTCQuoted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event OTCSwapped(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address indexed to);

    constructor(address _pass) {
        require(_pass != address(0), "invalid pass");
        pass = IPASSOtc(_pass);
    }

    modifier onlyProtocol() {
        require(routers[msg.sender] || strategies[msg.sender], "Not authorized");
        _;
    }

    function setRouter(address router, bool allowed) external onlyOwner {
        routers[router] = allowed;
        emit RouterSet(router, allowed);
    }

    function setStrategy(address strategy, bool allowed) external onlyOwner {
        strategies[strategy] = allowed;
        emit StrategySet(strategy, allowed);
    }

    function quoteOTC(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        amountOut = pass.quote(tokenIn, tokenOut, amountIn);
        emit OTCQuoted(tokenIn, tokenOut, amountIn, amountOut);
    }

    function swapOTC(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address to
    ) external onlyProtocol returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeApprove(address(pass), 0);
        IERC20(tokenIn).safeApprove(address(pass), amountIn);
        amountOut = pass.swap(tokenIn, tokenOut, amountIn, minAmountOut, to);
        emit OTCSwapped(tokenIn, tokenOut, amountIn, amountOut, to);
    }
}

