// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IUniswapV2RouterLike {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IPlatypusRouter {
    function getQuoteFromPool(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);
    function getCoverageRatio(address token) external view returns (uint256);
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address to
    ) external returns (uint256 amountOut);
}

/// @title PlatypusSwapRoute
/// @notice Compares stablecoin swap quotes across DEXes and optionally routes through Platypus
contract PlatypusSwapRoute is Ownable {
    using SafeERC20 for IERC20;

    /// @notice UniswapV2-style routers to compare against (e.g., Trader Joe, Pangolin)
    IUniswapV2RouterLike[] public dexRouters;
    /// @notice Platypus router for stablecoin swaps
    IPlatypusRouter public platypusRouter;

    /// @notice Enable or disable routing through Platypus
    bool public platypusEnabled = true;
    /// @notice Maximum input amount allowed per trade when routing through Platypus
    uint256 public platypusTradeCap = type(uint256).max;


    event DexRouterAdded(address indexed router);
    event DexRouterRemoved(address indexed router);

    /// @notice Minimum acceptable coverage ratio (scaled to 1e18)
    uint256 public minCoverageRatio;

    /// @notice Emitted after checking coverage ratio for a token
    event CoverageRatioChecked(address indexed token, uint256 ratio);

    /// @notice Emitted when the kill‑switch disables Platypus routing
    event KillSwitchActivated(address indexed token, uint256 ratio);


    constructor(address _platypusRouter, address[] memory _dexRouters) {
        require(_platypusRouter != address(0), "platypus router addr zero");
        platypusRouter = IPlatypusRouter(_platypusRouter);
        for (uint256 i = 0; i < _dexRouters.length; i++) {
            require(_dexRouters[i] != address(0), "router addr zero");
            dexRouters.push(IUniswapV2RouterLike(_dexRouters[i]));
        }
    }

    /// @notice Update whether Platypus routing is enabled
    function setPlatypusEnabled(bool enabled) external onlyOwner {
        platypusEnabled = enabled;
    }

    /// @notice Update the per-trade size cap for Platypus routing
    function setPlatypusTradeCap(uint256 cap) external onlyOwner {
        platypusTradeCap = cap;
    }

    /// @notice Update the minimum coverage ratio required to use Platypus
    function setMinCoverageRatio(uint256 ratio) external onlyOwner {
        minCoverageRatio = ratio;
    }

    /// @notice Add an additional UniswapV2-style router to compare against
    function addDexRouter(address router) external onlyOwner {
        require(router != address(0), "router addr zero");
        dexRouters.push(IUniswapV2RouterLike(router));
        emit DexRouterAdded(router);
    }

    function removeDexRouter(address router) external onlyOwner {
        require(router != address(0), "router addr zero");
        uint256 len = dexRouters.length;
        for (uint256 i = 0; i < len; i++) {
            if (address(dexRouters[i]) == router) {
                dexRouters[i] = dexRouters[len - 1];
                dexRouters.pop();
                emit DexRouterRemoved(router);
                return;
            }
        }
        revert("router not found");
    }

    /// @dev Determine the best quote among configured routers and Platypus
    function _bestQuote(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut, bool usePlatypus, uint8 index) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        for (uint8 i = 0; i < dexRouters.length; i++) {
            uint[] memory amounts = dexRouters[i].getAmountsOut(amountIn, path);
            uint out = amounts[amounts.length - 1];
            if (out > amountOut) {
                amountOut = out;
                usePlatypus = false;
                index = i;
            }
        }

        if (platypusEnabled && amountIn <= platypusTradeCap && _checkCoverage(tokenIn) && _checkCoverage(tokenOut)) {
            uint platQuote = platypusRouter.getQuoteFromPool(tokenIn, tokenOut, amountIn);
            if (platQuote > amountOut) {
                amountOut = platQuote;
                usePlatypus = true;
            }
        }
    }

    /// @dev Check coverage ratio and trigger kill‑switch if below threshold
    function _checkCoverage(address token) internal returns (bool) {
        uint256 ratio = platypusRouter.getCoverageRatio(token);
        emit CoverageRatioChecked(token, ratio);
        if (ratio < minCoverageRatio) {
            if (platypusEnabled) {
                platypusEnabled = false;
                emit KillSwitchActivated(token, ratio);
            }
            return false;
        }
        return true;
    }

    /// @notice Swap tokens using the best available route
    /// @param tokenIn Token being sold
    /// @param tokenOut Token being bought
    /// @param amountIn Amount of tokenIn to swap
    /// @param minAmountOut Minimum acceptable amount of tokenOut
    /// @param to Recipient of tokenOut
    /// @return amountOut Actual amount of tokenOut received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address to
    ) external returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        (uint256 best, bool usePlat, uint8 index) = _bestQuote(tokenIn, tokenOut, amountIn);
        require(best >= minAmountOut, "INSUFFICIENT_OUTPUT_AMOUNT");

        if (usePlat) {
            IERC20(tokenIn).safeApprove(address(platypusRouter), 0);
            IERC20(tokenIn).safeApprove(address(platypusRouter), amountIn);
            amountOut = platypusRouter.swap(tokenIn, tokenOut, amountIn, minAmountOut, address(this));
        } else {
            IUniswapV2RouterLike router = dexRouters[index];
            IERC20(tokenIn).safeApprove(address(router), 0);
            IERC20(tokenIn).safeApprove(address(router), amountIn);
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            uint[] memory amounts = router.swapExactTokensForTokens(amountIn, minAmountOut, path, address(this), block.timestamp);
            amountOut = amounts[amounts.length - 1];
        }

        IERC20(tokenOut).safeTransfer(to, amountOut);
    }
}

