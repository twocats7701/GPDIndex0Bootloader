// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./GPDYieldVault0.sol";
import "./IBlackholeBribe.sol";

interface IBlackholePool {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function claim() external returns (uint256);
}

contract BlackholeDexStrategy is Ownable, ReentrancyGuard, IYieldStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable depositToken;
    address public vault;
    IBlackholePool public pool;
    IBlackholeBribe public bribeManager;

    event EmergencyWithdraw(uint256 stakedAmount, uint256 rewardAmount);

    constructor(address _token, address _pool) {
        require(_token != address(0) && _pool != address(0), "Invalid addresses");
        depositToken = IERC20(_token);
        pool = IBlackholePool(_pool);
        depositToken.safeApprove(_pool, type(uint256).max);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Not authorized");
        _;
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault");
        vault = _vault;
    }

    function setPool(address _pool) external onlyOwner {
        require(_pool != address(0), "Invalid pool");
        depositToken.safeApprove(address(pool), 0);
        pool = IBlackholePool(_pool);
        depositToken.safeApprove(_pool, type(uint256).max);
    }

    function setBribeManager(address _manager) external onlyOwner {
        bribeManager = IBlackholeBribe(_manager);
    }

    function _deposit(uint256 amount) internal {
        depositToken.safeTransferFrom(msg.sender, address(this), amount);
        pool.deposit(amount);
    }

    function deposit(uint256 amount) external onlyVault nonReentrant {
        _deposit(amount);
    }

    function deposit(uint256 amount, uint256 /*slippageBpsOverride*/) external onlyVault nonReentrant {
        _deposit(amount);
    }

    function _withdraw(uint256 amount) internal {
        pool.withdraw(amount);
        depositToken.safeTransfer(vault, amount);
    }

    function withdraw(uint256 amount) external onlyVault nonReentrant {
        _withdraw(amount);
    }

    function withdraw(uint256 amount, uint256 /*slippageBpsOverride*/) external onlyVault nonReentrant {
        _withdraw(amount);
    }

    function totalAssets() external view returns (uint256) {
        return pool.balanceOf(address(this));
    }

    function harvest(uint256) external onlyVault nonReentrant returns (uint256) {
        uint256 amount = pool.claim();
        if (amount > 0) {
            depositToken.safeTransfer(vault, amount);
        }
        uint256 bribeAmt;
        if (address(bribeManager) != address(0)) {
            bribeAmt = bribeManager.claimBribe(address(depositToken));
            if (bribeAmt > 0) {
                depositToken.safeTransfer(vault, bribeAmt);
            }
        }
        return amount + bribeAmt;
    }

    /// @notice Withdraw all staked tokens and rewards to the vault
    function emergencyWithdraw() external onlyOwner nonReentrant {
        uint256 staked = pool.balanceOf(address(this));
        if (staked > 0) {
            pool.withdraw(staked);
        }
        uint256 rewards = pool.claim();
        uint256 bal = depositToken.balanceOf(address(this));
        if (bal > 0) {
            depositToken.safeTransfer(vault, bal);
        }
        emit EmergencyWithdraw(staked, rewards);
    }
}

