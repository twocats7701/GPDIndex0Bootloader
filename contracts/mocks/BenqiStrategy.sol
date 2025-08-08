// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./GPDYieldVault0.sol";

interface IQiToken {
    function mint(uint256 mintAmount) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function exchangeRateStored() external view returns (uint256);
}

interface IQiController {
    function claimReward(uint8 rewardType, address holder, address[] calldata qiTokens) external;
}

interface IUniswapV2Router {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract BenqiStrategy is Ownable, IYieldStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlying;
    IERC20 public immutable rewardToken; // QI
    IQiToken public immutable qiToken;
    IQiController public immutable controller;
    IUniswapV2Router public immutable router;

    address public vault;
    uint256 public totalSupplied;
    address[] public rewardToUnderlyingPath;
    /// @notice Global slippage tolerance in basis points for reward swaps
    /// @dev Defaults to 50 bps (0.5%) and can be overridden per call
    uint256 public slippageBps = 50;

    constructor(
        address _underlying,
        address _qiToken,
        address _controller,
        address _router,
        address[] memory _path
    ) {
        underlying = IERC20(_underlying);
        qiToken = IQiToken(_qiToken);
        controller = IQiController(_controller);
        router = IUniswapV2Router(_router);
        rewardToUnderlyingPath = _path;
        rewardToken = IERC20(_path[0]);

        IERC20(_underlying).safeApprove(_qiToken, type(uint256).max);
        IERC20(_path[0]).safeApprove(_router, type(uint256).max);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Not authorized");
        _;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    /// @notice Update the slippage tolerance in basis points
    /// @param newBps The new slippage amount where 100 bps = 1%
    function setSlippageBps(uint256 newBps) external onlyOwner {
        slippageBps = newBps;
    }

    function deposit(uint256 amount) external onlyVault {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        require(qiToken.mint(amount) == 0, "Mint failed");
        totalSupplied += amount;
    }

    function withdraw(uint256 amount) external onlyVault {
        require(qiToken.redeemUnderlying(amount) == 0, "Redeem failed");
        underlying.safeTransfer(vault, amount);
        if (totalSupplied >= amount) {
            totalSupplied -= amount;
        } else {
            totalSupplied = 0;
        }
    }

    function totalAssets() external view returns (uint256) {
        uint256 cBalance = qiToken.balanceOf(address(this));
        uint256 exchangeRate = qiToken.exchangeRateStored();
        return (cBalance * exchangeRate) / 1e18;
    }

    function harvest(uint256 slippageBpsOverride) external onlyVault returns (uint256) {
        address[] memory qiTokens = new address[](1);
        qiTokens[0] = address(qiToken);
        controller.claimReward(0, address(this), qiTokens);

        uint256 rewardBal = rewardToken.balanceOf(address(this));
        if (rewardBal == 0) {
            return 0;
        }
        uint256[] memory quote = router.getAmountsOut(rewardBal, rewardToUnderlyingPath);
        uint256 expected = quote[quote.length - 1];
        uint256 bps = slippageBpsOverride == 0 ? slippageBps : slippageBpsOverride;
        uint256 minOut = (expected * (10_000 - bps)) / 10_000;

        uint256[] memory amounts = router.swapExactTokensForTokens(
            rewardBal,
            minOut,
            rewardToUnderlyingPath,
            vault,
            block.timestamp
        );

        return amounts[amounts.length - 1];
    }
}

