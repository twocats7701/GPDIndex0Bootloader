// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IRouterPull {
    function pull(address token, address from, address to, uint256 amount) external;
}

library SafeOpsRestrictedToken {
    using SafeERC20 for IERC20;

    struct AssetConfig {
        bool sellEnabled;
        uint256 maxSlippageBps; // allowed slippage when sells enabled
        uint256 maxSize; // max size when sells enabled
        uint256 maxSlippageBpsWhenDisabled; // allowed slippage when sells disabled
        uint256 maxSizeWhenDisabled; // max size when sells disabled
        address router; // router used for pull fallback
    }

    error SizeExceeded();
    error SlippageExceeded();

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 amount,
        AssetConfig storage cfg
    ) internal {
        _checkSize(amount, cfg);
        if (_tryStaticCall(address(token), abi.encodeWithSelector(token.transfer.selector, to, amount))) {
            token.safeTransfer(to, amount);
        } else {
            _routerPull(token, address(this), to, amount, cfg);
        }
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 amount,
        AssetConfig storage cfg
    ) internal {
        _checkSize(amount, cfg);
        if (_tryStaticCall(address(token), abi.encodeWithSelector(token.transferFrom.selector, from, to, amount))) {
            token.safeTransferFrom(from, to, amount);
        } else {
            _routerPull(token, from, to, amount, cfg);
        }
    }

    function checkSlippage(
        uint256 expected,
        uint256 actual,
        AssetConfig storage cfg
    ) internal view {
        uint256 limit = cfg.sellEnabled ? cfg.maxSlippageBps : cfg.maxSlippageBpsWhenDisabled;
        if (expected == 0) return;
        uint256 diff = expected > actual ? expected - actual : actual - expected;
        uint256 bps = diff * 10000 / expected;
        if (bps > limit) revert SlippageExceeded();
    }

    function setSellEnabled(AssetConfig storage cfg, bool enabled) internal {
        cfg.sellEnabled = enabled;
    }

    function _checkSize(uint256 amount, AssetConfig storage cfg) private view {
        uint256 limit = cfg.sellEnabled ? cfg.maxSize : cfg.maxSizeWhenDisabled;
        if (amount > limit) revert SizeExceeded();
    }

    function _tryStaticCall(address token, bytes memory data) private view returns (bool) {
        (bool success, bytes memory ret) = token.staticcall(data);
        return success && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    function _routerPull(
        IERC20 token,
        address from,
        address to,
        uint256 amount,
        AssetConfig storage cfg
    ) private {
        address router = cfg.router;
        require(router != address(0), "router required");
        if (from == address(this)) {
            token.safeApprove(router, 0);
            token.safeApprove(router, amount);
        }
        IRouterPull(router).pull(address(token), from, to, amount);
        if (from == address(this)) {
            token.safeApprove(router, 0);
        }
    }
}
