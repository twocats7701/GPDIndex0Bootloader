// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RewardEscrow
 * @notice Holds tokens in time-locked vesting schedules.
 */
contract RewardEscrow {
    using SafeERC20 for IERC20;

    address public owner;
    IERC20 public rewardToken;

    struct Vesting {
        uint256 amount;
        uint256 releaseTime;
    }

    mapping(address => Vesting[]) public vestings;

    event RewardDeposited(address indexed user, uint256 amount, uint256 releaseTime);
    event RewardClaimed(address indexed user, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _token) {
        owner = msg.sender;
        rewardToken = IERC20(_token);
    }

    function deposit(address user, uint256 amount, uint256 delay) external onlyOwner {
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 release = block.timestamp + delay;
        vestings[user].push(Vesting(amount, release));
        emit RewardDeposited(user, amount, release);
    }

    function claim() external {
        uint256 total;
        Vesting[] storage userVests = vestings[msg.sender];
        for (uint256 i = 0; i < userVests.length; i++) {
            if (userVests[i].releaseTime <= block.timestamp && userVests[i].amount > 0) {
                total += userVests[i].amount;
                userVests[i].amount = 0;
            }
        }
        require(total > 0, "No rewards");
        rewardToken.safeTransfer(msg.sender, total);
        emit RewardClaimed(msg.sender, total);
    }

    function totalEscrowed(address user) external view returns (uint256 total) {
        Vesting[] storage userVests = vestings[user];
        for (uint256 i = 0; i < userVests.length; i++) {
            if (userVests[i].amount > 0) {
                total += userVests[i].amount;
            }
        }
    }
}

