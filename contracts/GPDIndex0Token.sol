// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GPDIndex0 Token with Vote-Escrow Locking
 * @dev ERC20 token extended with simple lock/escrow mechanics for ve power.
 *      Users can lock tokens for a duration to obtain vote-escrow (ve) power.
 *      ve power decays linearly over the lock period and is exposed via
 *      `balanceOf`.
 *      Integration hooks for Blackhole DEX rewards are provided through the
 *      `notifyReward` function which can be called by an authorised distributor.
 */
contract GPDIndex0Token is ERC20, Ownable {
    struct LockedBalance {
        uint256 amount;       // amount of tokens locked
        uint256 unlockTime;   // timestamp when tokens unlock
    }

    mapping(address => LockedBalance) public locks;

    uint256 public constant MAX_LOCK_DURATION = 52 weeks;

    address public rewardDistributor;

    // -------------------------------------------------------------
    //                         Events
    // -------------------------------------------------------------
    event Locked(address indexed user, uint256 amount, uint256 unlockTime);
    event LockExtended(address indexed user, uint256 unlockTime);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardDistributorSet(address distributor);
    event RewardNotified(address indexed user, uint256 amount);

    constructor(uint256 initialSupply) ERC20("GPINDEX0", "GPINDEX0") {
        _mint(msg.sender, initialSupply);
    }

    // -------------------------------------------------------------
    //                       Locking logic
    // -------------------------------------------------------------

    /**
     * @notice Lock tokens for `duration` to gain ve power.
     * @param amount Amount of tokens to lock.
     * @param duration Duration of the lock in seconds (max 52 weeks).
     */
    function lock(uint256 amount, uint256 duration) external {
        require(amount > 0, "Amount must be > 0");
        require(duration > 0 && duration <= MAX_LOCK_DURATION, "Invalid duration");

        LockedBalance storage lockInfo = locks[msg.sender];
        require(lockInfo.amount == 0, "Existing lock");

        _transfer(msg.sender, address(this), amount);

        lockInfo.amount = amount;
        lockInfo.unlockTime = block.timestamp + duration;

        emit Locked(msg.sender, amount, lockInfo.unlockTime);
    }

    /**
     * @notice Extend an existing lock by `additionalDuration` seconds.
     * @param additionalDuration Additional lock time in seconds.
     */
    function extendLock(uint256 additionalDuration) external {
        LockedBalance storage lockInfo = locks[msg.sender];
        require(lockInfo.amount > 0, "No active lock");
        require(additionalDuration > 0, "Duration must be > 0");

        uint256 newUnlock = lockInfo.unlockTime + additionalDuration;
        require(newUnlock - block.timestamp <= MAX_LOCK_DURATION, "Lock too long");

        lockInfo.unlockTime = newUnlock;

        emit LockExtended(msg.sender, newUnlock);
    }

    /**
     * @notice Withdraw locked tokens after lock expiry.
     */
    function withdraw() external {
        LockedBalance storage lockInfo = locks[msg.sender];
        require(lockInfo.amount > 0, "No active lock");
        require(block.timestamp >= lockInfo.unlockTime, "Lock not expired");

        uint256 amount = lockInfo.amount;
        lockInfo.amount = 0;
        lockInfo.unlockTime = 0;

        _transfer(address(this), msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    // -------------------------------------------------------------
    //                      View functions
    // -------------------------------------------------------------

    /**
     * @notice Returns vote-escrowed balance (ve power).
     * @dev Balance decays linearly to zero as unlock time approaches.
     */
    function balanceOf(address account) public view override returns (uint256) {
        LockedBalance memory lockInfo = locks[account];
        if (lockInfo.amount == 0 || block.timestamp >= lockInfo.unlockTime) {
            return 0;
        }
        uint256 remaining = lockInfo.unlockTime - block.timestamp;
        return lockInfo.amount * remaining / MAX_LOCK_DURATION;
    }

    /**
     * @notice Returns the actual ERC20 token balance of `account`.
     * @dev Use this instead of `balanceOf` to get current token holdings.
     */
    function tokenBalanceOf(address account) public view returns (uint256) {
        return super.balanceOf(account);
    }

    // -------------------------------------------------------------
    //                Blackhole DEX reward integration
    // -------------------------------------------------------------

    /**
     * @notice Set the authorised reward distributor contract.
     */
    function setRewardDistributor(address distributor) external onlyOwner {
        rewardDistributor = distributor;
        emit RewardDistributorSet(distributor);
    }

    /**
     * @notice Hook for Blackhole DEX to notify reward distribution.
     * @dev Currently emits an event; accounting is expected to be handled
     *      off-chain or by the distributor.
     */
    function notifyReward(address user, uint256 amount) external {
        require(msg.sender == rewardDistributor, "Not distributor");
        emit RewardNotified(user, amount);
    }
}

