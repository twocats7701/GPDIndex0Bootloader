// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBlackholeBribe.sol";

contract BlackholeBribeManager is Ownable, IBlackholeBribe {
    using SafeERC20 for IERC20;

    // simple storage for bribe balances by token
    mapping(address => uint256) public bribeBalances;

    function depositBribe(address token, uint256 amount) external override {
        require(amount > 0, "amount=0");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        bribeBalances[token] += amount;
    }

    function claimBribe(address token) external override returns (uint256) {
        uint256 amount = bribeBalances[token];
        if (amount > 0) {
            bribeBalances[token] = 0;
            IERC20(token).safeTransfer(msg.sender, amount);
        }
        return amount;
    }

    function notifyBribe(address token, uint256 amount) external override {
        require(amount > 0, "amount=0");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        bribeBalances[token] += amount;
    }
}

