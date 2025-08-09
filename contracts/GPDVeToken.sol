// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title GPDVeToken
/// @notice Minimal vote escrow implementation with linear time decay.
/// Users lock an underlying token for up to `MAX_TIME` and receive
/// non-transferable voting power weighted by lock duration.
contract GPDVeToken is ERC20 {
    using SafeERC20 for IERC20;

    struct LockedBalance {
        uint256 amount;       // amount of underlying tokens locked
        uint256 unlockTime;   // timestamp when tokens can be withdrawn
    }

    IERC20 public immutable stakeToken;
    uint256 public constant MAX_TIME = 365 days; // maximum lock duration

    mapping(address => LockedBalance) public locked;

    event Locked(address indexed user, uint256 amount, uint256 unlockTime);
    event Extended(address indexed user, uint256 newUnlockTime);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(address _stakeToken)
        ERC20("GPD Vote Escrow", "veGPD")
    {
        stakeToken = IERC20(_stakeToken);
    }

    /// ---------------------------------------------------------------------
    /// User actions
    /// ---------------------------------------------------------------------

    function lock(uint256 amount, uint256 duration) external {
        require(amount > 0, "lock amount = 0");
        require(duration > 0 && duration <= MAX_TIME, "bad duration");

        LockedBalance storage user = locked[msg.sender];
        require(user.amount == 0, "use increaseLock");

        uint256 unlockTime = block.timestamp + duration;
        user.amount = amount;
        user.unlockTime = unlockTime;

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Locked(msg.sender, amount, unlockTime);
    }

    /// @notice Increase lock amount and/or extend duration
    function increaseLock(uint256 amount, uint256 additionalDuration) external {
        LockedBalance storage user = locked[msg.sender];
        require(user.amount > 0, "no existing lock");
        if (amount > 0) {
            stakeToken.safeTransferFrom(msg.sender, address(this), amount);
            user.amount += amount;
        }
        if (additionalDuration > 0) {
            uint256 newUnlock = user.unlockTime + additionalDuration;
            require(newUnlock - block.timestamp <= MAX_TIME, "exceeds max time");
            user.unlockTime = newUnlock;
            emit Extended(msg.sender, newUnlock);
        }
        if (amount > 0) {
            emit Locked(msg.sender, user.amount, user.unlockTime);
        }
    }

    function withdraw() external {
        LockedBalance storage user = locked[msg.sender];
        require(block.timestamp >= user.unlockTime, "locked");
        uint256 amount = user.amount;
        require(amount > 0, "nothing to withdraw");
        user.amount = 0;
        user.unlockTime = 0;
        stakeToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// ---------------------------------------------------------------------
    /// Views
    /// ---------------------------------------------------------------------

    /// @notice Voting power = amount * remainingTime / MAX_TIME
    function balanceOf(address account) public view override returns (uint256) {
        LockedBalance memory user = locked[account];
        if (block.timestamp >= user.unlockTime) return 0;
        uint256 remaining = user.unlockTime - block.timestamp;
        return (user.amount * remaining) / MAX_TIME;
    }

    /// Non-transferable token
    function _transfer(address from, address to, uint256 value) internal override {
        // prohibit transfers except minting/burning
        require(from == address(0) || to == address(0), "non-transferable");
        super._transfer(from, to, value);
    }
}

