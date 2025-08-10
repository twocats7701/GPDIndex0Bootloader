// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/SafeOpsRestrictedToken.sol";

contract SafeOpsTester {
    using SafeERC20 for IERC20;
    using SafeOpsRestrictedToken for SafeOpsRestrictedToken.AssetConfig;

    mapping(address => SafeOpsRestrictedToken.AssetConfig) public configs;

    function setConfig(
        address token,
        address router,
        bool sellEnabled,
        uint256 maxSlippageBps,
        uint256 maxSize,
        uint256 maxSlippageBpsWhenDisabled,
        uint256 maxSizeWhenDisabled
    ) external {
        SafeOpsRestrictedToken.AssetConfig storage cfg = configs[token];
        cfg.router = router;
        cfg.sellEnabled = sellEnabled;
        cfg.maxSlippageBps = maxSlippageBps;
        cfg.maxSize = maxSize;
        cfg.maxSlippageBpsWhenDisabled = maxSlippageBpsWhenDisabled;
        cfg.maxSizeWhenDisabled = maxSizeWhenDisabled;
    }

    function transferRestricted(address token, address to, uint256 amount) external {
        SafeOpsRestrictedToken.safeTransfer(IERC20(token), to, amount, configs[token]);
    }

    function transferFromRestricted(address token, address from, address to, uint256 amount) external {
        SafeOpsRestrictedToken.safeTransferFrom(IERC20(token), from, to, amount, configs[token]);
    }

    function checkSlippage(address token, uint256 expected, uint256 actual) external view {
        SafeOpsRestrictedToken.checkSlippage(expected, actual, configs[token]);
    }

    function setSellEnabled(address token, bool enabled) external {
        SafeOpsRestrictedToken.setSellEnabled(configs[token], enabled);
    }
}
