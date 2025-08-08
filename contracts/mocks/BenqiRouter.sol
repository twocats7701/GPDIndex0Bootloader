// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IQiErc20 {
    function mint(uint256 mintAmount) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function balanceOfUnderlying(address owner) external returns (uint256);
    function exchangeRateStored() external view returns (uint256);
}

contract BenqiRouter is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlying; // e.g. USDC, USDT
    IQiErc20 public immutable qiToken; // e.g. qiUSDC, qiUSDT

    constructor(address _underlying, address _qiToken) {
        underlying = IERC20(_underlying);
        qiToken = IQiErc20(_qiToken);
        IERC20(_underlying).safeApprove(_qiToken, type(uint256).max);
    }

    /// @notice Supply `amount` to Benqi Lending
    function deposit(uint256 amount) external onlyOwner {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        require(qiToken.mint(amount) == 0, "Mint failed");
    }

    /// @notice Withdraw underlying token from Benqi Lending
    function withdraw(uint256 amount) external onlyOwner {
        require(qiToken.redeemUnderlying(amount) == 0, "Redeem failed");
        underlying.safeTransfer(msg.sender, amount);
    }

    /// @notice Returns the amount of underlying token supplied

    function balance() external returns (uint256) {
        return qiToken.balanceOfUnderlying(address(this));
    }

    /// @notice Returns the current exchange rate
    function exchangeRate() external view returns (uint256) {
        return qiToken.exchangeRateStored();
    }
}

