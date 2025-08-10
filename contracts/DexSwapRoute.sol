// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IAssetPolicy.sol";
import "./interfaces/IUniswapV2RouterLike.sol";
import "./interfaces/IPlatypusRouter.sol";
import "./AssetPolicy.sol";
/// @title DexSwapRoute
/// @notice Compares token swap quotes across DEXes and optionally routes through Platypus
contract DexSwapRoute is Ownable {
    using SafeERC20 for IERC20;

    /// @notice UniswapV2-style routers to compare against (e.g., Trader Joe, Pangolin)
    IUniswapV2RouterLike[] public dexRouters;
    /// @notice Platypus router for token swaps
    IPlatypusRouter public platypusRouter;

    /// @notice Optional policy contract controlling DEX sells
    AssetPolicy public assetPolicy;

    /// @notice Enable or disable routing through Platypus
    bool public platypusEnabled = false;
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
        require(_dexRouters.length > 0, "at least one router");
        platypusRouter = IPlatypusRouter(_platypusRouter);
        for (uint256 i = 0; i < _dexRouters.length; i++) {
            require(_dexRouters[i] != address(0), "router addr zero");
            dexRouters.push(IUniswapV2RouterLike(_dexRouters[i]));
        }
    }

    /// @notice Set the asset policy contract
    function setAssetPolicy(address policy) external onlyOwner {
        assetPolicy = AssetPolicy(policy);
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
        require(len > 1, "at least one router");
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

    /// @notice Return the best quote among all configured routes
    /// @param path Swap path from tokenIn to tokenOut
    /// @param amountIn Amount of tokenIn to swap
    /// @return amountOut Best obtainable amount of tokenOut
    function getBestQuote(address[] calldata path, uint256 amountIn) external view returns (uint256 amountOut) {
        require(path.length >= 2, "invalid path");
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];
        bool anyAllowed;

        for (uint8 i = 0; i < dexRouters.length; i++) {
            address routerAddr = address(dexRouters[i]);
            if (address(assetPolicy) != address(0) && !assetPolicy.allowedRouters(tokenIn, routerAddr)) {
                continue;
            }
            anyAllowed = true;
            try dexRouters[i].getAmountsOut(amountIn, path) returns (uint[] memory amounts) {
                uint out = amounts[amounts.length - 1];
                if (out > amountOut) {
                    amountOut = out;
                }
            } catch {
                continue;
            }
        }

        if (
            platypusEnabled &&
            path.length == 2 &&
            amountIn <= platypusTradeCap &&
            (address(assetPolicy) == address(0) || assetPolicy.allowedRouters(tokenIn, address(platypusRouter)))
        ) {
            anyAllowed = true;
            try platypusRouter.getQuoteFromPool(tokenIn, tokenOut, amountIn) returns (uint platQuote) {
                if (platQuote > amountOut) {
                    amountOut = platQuote;
                }
            } catch {
                // ignore failures and fall back to DEX routers
            }
        }

        require(anyAllowed, "NO_VALID_ROUTERS");
    }

    /// @dev Determine the best quote among configured routers and Platypus
    function _bestQuote(address[] memory path, uint256 amountIn)
        internal
        returns (uint256 amountOut, bool usePlatypus, uint8 index)
    {
        require(path.length >= 2, "invalid path");
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];
        bool anyAllowed;

        for (uint8 i = 0; i < dexRouters.length; i++) {
            address routerAddr = address(dexRouters[i]);
            if (address(assetPolicy) != address(0) && !assetPolicy.allowedRouters(tokenIn, routerAddr)) {
                continue;
            }
            anyAllowed = true;
            try dexRouters[i].getAmountsOut(amountIn, path) returns (uint[] memory amounts) {
                uint out = amounts[amounts.length - 1];
                if (out > amountOut) {
                    amountOut = out;
                    usePlatypus = false;
                    index = i;
                }
            } catch {
                continue;
            }
        }

        if (
            platypusEnabled &&
            path.length == 2 &&
            amountIn <= platypusTradeCap &&
            (address(assetPolicy) == address(0) || assetPolicy.allowedRouters(tokenIn, address(platypusRouter))) &&
            _checkCoverage(tokenIn) &&
            _checkCoverage(tokenOut)
        ) {
            anyAllowed = true;
            try platypusRouter.getQuoteFromPool(tokenIn, tokenOut, amountIn) returns (uint platQuote) {
                if (platQuote > amountOut) {
                    amountOut = platQuote;
                    usePlatypus = true;
                }
            } catch {
                // ignore failures and fall back to DEX routers
            }
        }

        require(anyAllowed, "NO_VALID_ROUTERS");
    }

    /// @dev Check coverage ratio and trigger kill‑switch if below threshold
    function _checkCoverage(address token) internal returns (bool) {
        try platypusRouter.getCoverageRatio(token) returns (uint256 ratio) {
            emit CoverageRatioChecked(token, ratio);
            if (ratio < minCoverageRatio) {
                if (platypusEnabled) {
                    platypusEnabled = false;
                    emit KillSwitchActivated(token, ratio);
                }
                return false;
            }
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Swap tokens using the best available route
    /// @param path Swap path from tokenIn to tokenOut
    /// @param amountIn Amount of tokenIn to swap
    /// @param minAmountOut Minimum acceptable amount of tokenOut
    /// @param to Recipient of tokenOut
    /// @return amountOut Actual amount of tokenOut received
    function swap(
        address[] calldata path,
        uint256 amountIn,
        uint256 minAmountOut,
        address to
    ) external returns (uint256 amountOut) {
        require(path.length >= 2, "invalid path");
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        (uint256 best, bool usePlat, uint8 index) = _bestQuote(path, amountIn);
        require(best >= minAmountOut, "INSUFFICIENT_OUTPUT_AMOUNT");

        address routerAddr = usePlat ? address(platypusRouter) : address(dexRouters[index]);
        if (address(assetPolicy) != address(0)) {
            require(assetPolicy.allowedRouters(tokenIn, routerAddr), "ROUTER_NOT_ALLOWED");
            uint256 price = (best * 1e18) / amountIn;
            require(assetPolicy.isDexSellAllowed(tokenIn, price), "SELL_NOT_ALLOWED");
        }

        if (usePlat) {
            IERC20(tokenIn).safeApprove(address(platypusRouter), 0);
            IERC20(tokenIn).safeApprove(address(platypusRouter), amountIn);
            amountOut = platypusRouter.swap(tokenIn, tokenOut, amountIn, minAmountOut, address(this));
        } else {
            IUniswapV2RouterLike router = dexRouters[index];
            IERC20(tokenIn).safeApprove(address(router), 0);
            IERC20(tokenIn).safeApprove(address(router), amountIn);
            uint[] memory amounts = router.swapExactTokensForTokens(amountIn, minAmountOut, path, address(this), block.timestamp);
            amountOut = amounts[amounts.length - 1];
        }

        IERC20(tokenOut).safeTransfer(to, amountOut);
    }
}

