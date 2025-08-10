// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./GPDYieldVault0.sol";
import "./interfaces/IDexSwapRoute.sol";
import "./OtcAdapterPASS.sol";

interface IMasterChef {
    function deposit(uint256 pid, uint256 amount) external;
    function withdraw(uint256 pid, uint256 amount) external;
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
    function pendingReward(uint256 pid, address user) external view returns (uint256);
}

/// @title VaporDexStrategy
/// @notice Stakes LP tokens in a Vapor Dex farm and compounds the rewards back into LP tokens
/// @dev Compatible with other Uniswap V2 style DEXs such as Pangolin by supplying appropriate addresses
contract VaporDexStrategy is Ownable, IYieldStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable lpToken;
    IERC20 public immutable rewardToken;
    IMasterChef public farm;
    IDexSwapRoute public swapRoute;
    OtcAdapterPASS public otcAdapter;
    address public vault;
    uint256 public immutable pid;
    address[] public rewardToLpPath;

    /// @notice Global slippage tolerance in basis points used for DEX operations
    /// @dev Defaults to 50 bps (0.5%) and can be overridden per call
    uint256 public slippageBps = 50;
    bool public isDexSellAllowed = true;

    event VaultUpdated(address indexed newVault);
    event SlippageBpsUpdated(uint256 newSlippageBps);
    event DexSellAllowedUpdated(bool allowed);
    event OtcAdapterUpdated(address indexed adapter);
    event EmergencyWithdraw(uint256 lpAmount, uint256 rewardAmount);

    constructor(
        address _lpToken,
        address _farm,
        uint256 _pid,
        address _rewardToken,
        address _swapRoute,
        address[] memory _path
    ) {
        lpToken = IERC20(_lpToken);
        farm = IMasterChef(_farm);
        pid = _pid;
        rewardToken = IERC20(_rewardToken);
        swapRoute = IDexSwapRoute(_swapRoute);
        require(_path.length >= 2, "invalid path");
        require(_path[0] == _rewardToken, "path start");
        require(_path[_path.length - 1] == _lpToken, "path end");
        rewardToLpPath = _path;

        lpToken.safeApprove(_farm, type(uint256).max);
        rewardToken.safeApprove(_swapRoute, type(uint256).max);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Not authorized");
        _;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
        emit VaultUpdated(_vault);
    }

    /// @notice Update the slippage tolerance in basis points
    /// @param newBps The new slippage amount where 100 bps = 1%
    function setSlippageBps(uint256 newBps) external onlyOwner {
        slippageBps = newBps;
        emit SlippageBpsUpdated(newBps);
    }

    function setDexSellAllowed(bool allowed) external onlyOwner {
        isDexSellAllowed = allowed;
        emit DexSellAllowedUpdated(allowed);
    }

    function setOtcAdapter(address adapter) external onlyOwner {
        otcAdapter = OtcAdapterPASS(adapter);
        emit OtcAdapterUpdated(adapter);
    }

    function _deposit(uint256 amount) internal {
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        farm.deposit(pid, amount);
    }

    function deposit(uint256 amount) external onlyVault {
        deposit(amount, 0);
    }

    function deposit(uint256 amount, uint256 /*slippageBpsOverride*/) public onlyVault {
        _deposit(amount);
    }

    function _withdraw(uint256 amount) internal {
        farm.withdraw(pid, amount);
        lpToken.safeTransfer(vault, amount);
    }

    function withdraw(uint256 amount) external onlyVault {
        withdraw(amount, 0);
    }

    function withdraw(uint256 amount, uint256 /*slippageBpsOverride*/) public onlyVault {
        _withdraw(amount);
    }

    function totalAssets() external view returns (uint256) {
        (uint256 staked, ) = farm.userInfo(pid, address(this));
        uint256 pending = farm.pendingReward(pid, address(this));

        if (pending > 0 && address(rewardToken) != address(lpToken)) {
            pending = swapRoute.getBestQuote(rewardToLpPath, pending);
        }

        return staked + pending;
    }

    function harvest(uint256 slippageBpsOverride) external onlyVault returns (uint256) {
        uint256 beforeBal = lpToken.balanceOf(address(this));
        farm.withdraw(pid, 0);

        uint256 rewardBal = rewardToken.balanceOf(address(this));
        if (rewardBal > 0 && address(rewardToken) != address(lpToken)) {
            uint256 expected;
            uint256 bps = slippageBpsOverride == 0 ? slippageBps : slippageBpsOverride;
            if (isDexSellAllowed) {
                expected = swapRoute.getBestQuote(rewardToLpPath, rewardBal);
                uint256 amountOutMin = (expected * (10_000 - bps)) / 10_000;
                swapRoute.swap(rewardToLpPath, rewardBal, amountOutMin, address(this));
            } else {
                require(address(otcAdapter) != address(0), "otc not set");
                expected = otcAdapter.quoteOTC(address(rewardToken), address(lpToken), rewardBal);
                uint256 amountOutMin = (expected * (10_000 - bps)) / 10_000;
                otcAdapter.swapOTC(address(rewardToken), address(lpToken), rewardBal, amountOutMin, address(this));
            }
        }

        uint256 harvested = lpToken.balanceOf(address(this)) - beforeBal;
        if (harvested > 0) {
            lpToken.safeTransfer(vault, harvested);
        }
        return harvested;
    }

    /// @notice Withdraw all staked LP and rewards back to the vault
    function emergencyWithdraw() external onlyOwner {
        (uint256 staked, ) = farm.userInfo(pid, address(this));
        if (staked > 0) {
            farm.withdraw(pid, staked);
        }
        // claim pending rewards
        farm.withdraw(pid, 0);

        uint256 lpBal = lpToken.balanceOf(address(this));
        if (lpBal > 0) {
            lpToken.safeTransfer(vault, lpBal);
        }

        uint256 rewardBal = rewardToken.balanceOf(address(this));
        if (rewardBal > 0) {
            rewardToken.safeTransfer(vault, rewardBal);
        }

        emit EmergencyWithdraw(lpBal, rewardBal);
    }
}

