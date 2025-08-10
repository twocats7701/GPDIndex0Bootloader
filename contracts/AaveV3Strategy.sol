// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./GPDYieldVault0.sol";
import "./FlashLoanExecutor.sol";
import "./interfaces/IAavePool.sol";
import "./interfaces/IDexSwapRoute.sol";

interface IRewardsController {
    function claimRewards(address[] calldata assets, uint256 amount, address to, address reward) external returns (uint256);
}

interface IFlashLoanSimpleReceiver {
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params) external returns (bool);
}

contract AaveV3Strategy is Ownable, ReentrancyGuard, IYieldStrategy, IFlashLoanSimpleReceiver {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlying;
    IERC20 public immutable rewardToken;
    IAavePool public immutable pool;
    IRewardsController public immutable rewardsController;
    IDexSwapRoute public immutable swapRoute;
    FlashLoanExecutor public immutable executor;

    address public vault;
    uint256 public totalSupplied;
    address[] public rewardToUnderlyingPath;
    uint256 public slippageBps = 50; // 0.5%

    modifier onlyVault() {
        require(msg.sender == vault, "Not authorized");
        _;
    }

    constructor(
        address _underlying,
        address _pool,
        address _rewardsController,
        address _swapRoute,
        address[] memory _path,
        address _executor
    ) {
        underlying = IERC20(_underlying);
        pool = IAavePool(_pool);
        rewardsController = IRewardsController(_rewardsController);
        swapRoute = IDexSwapRoute(_swapRoute);
        rewardToken = IERC20(_path[0]);
        rewardToUnderlyingPath = _path;
        executor = FlashLoanExecutor(_executor);

        underlying.safeApprove(_pool, type(uint256).max);
        rewardToken.safeApprove(_swapRoute, type(uint256).max);
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    /// @notice Update the slippage tolerance in basis points
    function setSlippageBps(uint256 newBps) external onlyOwner {
        require(newBps > 0, "bps too low");
        require(newBps <= 10_000, "bps too high");
        slippageBps = newBps;
    }

    function _deposit(uint256 amount) internal {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        pool.supply(address(underlying), amount, address(this), 0);
        totalSupplied += amount;
    }

    function deposit(uint256 amount) external onlyVault nonReentrant {
        _deposit(amount);
    }

    function deposit(uint256 amount, uint256 /*slippageBpsOverride*/) external onlyVault nonReentrant {
        _deposit(amount);
    }

    function _withdraw(uint256 amount) internal {
        uint256 withdrawn = pool.withdraw(address(underlying), amount, address(this));
        underlying.safeTransfer(vault, withdrawn);
        if (totalSupplied >= withdrawn) {
            totalSupplied -= withdrawn;
        } else {
            totalSupplied = 0;
        }
    }

    function withdraw(uint256 amount) external onlyVault nonReentrant {
        _withdraw(amount);
    }

    function withdraw(uint256 amount, uint256 /*slippageBpsOverride*/) external onlyVault nonReentrant {
        _withdraw(amount);
    }

    function totalAssets() external view returns (uint256) {
        return totalSupplied;
    }

    function harvest(uint256 slippageBpsOverride) external onlyVault nonReentrant returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = address(this); // unused in mock
        uint256 claimed = rewardsController.claimRewards(assets, type(uint256).max, address(this), rewardToUnderlyingPath[0]);
        if (claimed == 0) {
            return 0;
        }
        uint256 expected = swapRoute.getBestQuote(rewardToUnderlyingPath, claimed);
        uint256 bps = slippageBpsOverride == 0 ? slippageBps : slippageBpsOverride;
        uint256 minOut = (expected * (10_000 - bps)) / 10_000;
        return swapRoute.swap(rewardToUnderlyingPath, claimed, minOut, vault);
    }

    function leverage(uint256 amount) external onlyVault nonReentrant {
        pool.flashLoanSimple(address(this), address(underlying), amount, bytes(""), 0);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address,
        bytes calldata
    ) external override returns (bool) {
        require(msg.sender == address(pool), "Only pool");
        require(asset == address(underlying), "Invalid asset");
        underlying.safeTransfer(address(executor), amount);
        executor.execute(address(pool), asset, amount, premium, address(this));
        totalSupplied += amount;
        return true;
    }
}

