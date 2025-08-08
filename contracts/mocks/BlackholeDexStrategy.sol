// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./GPDYieldVault0.sol";

interface IBlackholePool {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function claim() external returns (uint256);
}

contract BlackholeDexStrategy is Ownable, IYieldStrategy {
    using SafeERC20 for IERC20;

    IERC20 public immutable depositToken;
    address public vault;
    IBlackholePool public pool;

    constructor(address _token, address _pool) {
        depositToken = IERC20(_token);
        pool = IBlackholePool(_pool);
        depositToken.safeApprove(_pool, type(uint256).max);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Not authorized");
        _;
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setPool(address _pool) external onlyOwner {
        depositToken.safeApprove(address(pool), 0);
        pool = IBlackholePool(_pool);
        depositToken.safeApprove(_pool, type(uint256).max);
    }

    function deposit(uint256 amount) external onlyVault {
        depositToken.safeTransferFrom(msg.sender, address(this), amount);
        pool.deposit(amount);
    }

    function withdraw(uint256 amount) external onlyVault {
        pool.withdraw(amount);
        depositToken.safeTransfer(vault, amount);
    }

    function totalAssets() external view returns (uint256) {
        return pool.balanceOf(address(this));
    }

    function harvest(uint256) external onlyVault returns (uint256) {
        uint256 amount = pool.claim();
        if (amount > 0) {
            depositToken.safeTransfer(vault, amount);
        }
        return amount;
    }
}

