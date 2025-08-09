// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IVotingEscrow {
    function balanceOf(address account) external view returns (uint256);
}

interface IBlackholePool {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function claim() external returns (uint256);
}

/// @title GPDGauge
/// @notice Gauge contract managing deposits, ve-weighted votes and reward boosts.
///         Each gauge is attached to a Blackhole DEX pool and distributes rewards
///         proportionally to deposit balances boosted by vote-escrow (ve) power.
contract GPDGauge is Ownable, IBlackholePool {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;
    IVotingEscrow public immutable veToken;
    IBlackholePool public pool;

    uint256 public constant DURATION = 7 days;

    uint256 public totalSupply;
    uint256 public totalBoostedSupply;
    uint256 public totalVeWeight;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public votes;
    mapping(address => uint256) public boostedBalances;

    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 public lastUpdateTime;
    uint256 public rewardRate;
    uint256 public periodFinish;

    address public rewardDistributor;

    // bribe token accounting
    address[] public bribeTokens;
    struct BribeData {
        uint256 rewardPerTokenStored;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewards;
        uint256 lastUpdateTime;
        uint256 rewardRate;
        uint256 periodFinish;
    }
    mapping(address => BribeData) public bribes;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(uint256 reward);
    event Voted(address indexed user, uint256 weight);
    event RewardDistributorSet(address distributor);
    event BribeAdded(address token, uint256 reward);

    constructor(
        address _stakingToken,
        address _rewardToken,
        address _veToken,
        address _pool
    ) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        veToken = IVotingEscrow(_veToken);
        pool = IBlackholePool(_pool);
        stakingToken.safeApprove(_pool, type(uint256).max);
    }

    // ------------------------------------------------------------------
    //                           Admin operations
    // ------------------------------------------------------------------

    function setRewardDistributor(address distributor) external onlyOwner {
        rewardDistributor = distributor;
        emit RewardDistributorSet(distributor);
    }

    function setPool(address _pool) external onlyOwner {
        stakingToken.safeApprove(address(pool), 0);
        pool = IBlackholePool(_pool);
        stakingToken.safeApprove(_pool, type(uint256).max);
    }

    // ------------------------------------------------------------------
    //                           Views
    // ------------------------------------------------------------------

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function boostedBalanceOf(address account) public view returns (uint256) {
        if (totalVeWeight == 0) {
            return balances[account];
        }
        return balances[account] + (balances[account] * votes[account]) / totalVeWeight;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalBoostedSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) /
            totalBoostedSupply;
    }

    function earned(address account) public view returns (uint256) {
        return
            (boostedBalances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) /
            1e18 +
            rewards[account];
    }

    // ------------------------------------------------------------------
    //                        Core gauge logic
    // ------------------------------------------------------------------

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _updateBribes(account);
        _;
    }

    function deposit(uint256 amount) external override updateReward(msg.sender) {
        require(amount > 0, "Cannot deposit 0");
        uint256 oldBoosted = boostedBalances[msg.sender];
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        pool.deposit(amount);
        balances[msg.sender] += amount;
        totalSupply += amount;
        _updateBoost(msg.sender, oldBoosted);
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external override updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        uint256 oldBoosted = boostedBalances[msg.sender];
        balances[msg.sender] -= amount;
        totalSupply -= amount;
        pool.withdraw(amount);
        stakingToken.safeTransfer(msg.sender, amount);
        _updateBoost(msg.sender, oldBoosted);
        emit Withdrawn(msg.sender, amount);
    }

    function claim() public override updateReward(msg.sender) returns (uint256) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
        for (uint256 i = 0; i < bribeTokens.length; ++i) {
            address token = bribeTokens[i];
            BribeData storage b = bribes[token];
            uint256 br = b.rewards[msg.sender];
            if (br > 0) {
                b.rewards[msg.sender] = 0;
                IERC20(token).safeTransfer(msg.sender, br);
            }
        }
        return reward;
    }

    function getReward() external returns (uint256) {
        return claim();
    }

    // ------------------------------------------------------------------
    //                           Voting logic
    // ------------------------------------------------------------------

    function vote() external updateReward(msg.sender) {
        _updateVote(msg.sender, veToken.balanceOf(msg.sender));
    }

    function tallyVotes(address[] calldata voters) external {
        for (uint256 i = 0; i < voters.length; ++i) {
            address voter = voters[i];
            rewardPerTokenStored = rewardPerToken();
            lastUpdateTime = lastTimeRewardApplicable();
            rewards[voter] = earned(voter);
            userRewardPerTokenPaid[voter] = rewardPerTokenStored;
            _updateVote(voter, veToken.balanceOf(voter));
        }
    }

    function _updateVote(address voter, uint256 newVote) internal {
        uint256 oldBoosted = boostedBalances[voter];
        uint256 oldVote = votes[voter];
        if (oldVote == newVote) return;
        votes[voter] = newVote;
        totalVeWeight = totalVeWeight - oldVote + newVote;
        _updateBoost(voter, oldBoosted);
        emit Voted(voter, newVote);
    }

    function _updateBoost(address account, uint256 oldBoosted) internal {
        uint256 newBoosted = boostedBalanceOf(account);
        boostedBalances[account] = newBoosted;
        totalBoostedSupply = totalBoostedSupply - oldBoosted + newBoosted;
    }

    // ------------------------------------------------------------------
    //                      Reward distribution logic
    // ------------------------------------------------------------------

    function notifyRewardAmount(uint256 reward) external updateReward(address(0)) {
        require(msg.sender == rewardDistributor || msg.sender == owner(), "Not authorized");
        rewardToken.safeTransferFrom(msg.sender, address(this), reward);
        _notifyReward(reward);
    }

    function harvestPool() external updateReward(address(0)) {
        uint256 reward = pool.claim();
        if (reward > 0) {
            _notifyReward(reward);
        }
    }

    function _notifyReward(uint256 reward) internal {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward / DURATION;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / DURATION;
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + DURATION;
        emit RewardAdded(reward);
    }

    function notifyBribe(address token, uint256 reward) external updateReward(address(0)) {
        IERC20(token).safeTransferFrom(msg.sender, address(this), reward);
        _notifyBribe(token, reward);
    }

    function _notifyBribe(address token, uint256 reward) internal {
        BribeData storage b = bribes[token];
        if (b.lastUpdateTime == 0) {
            bribeTokens.push(token);
        }
        if (block.timestamp >= b.periodFinish) {
            b.rewardRate = reward / DURATION;
        } else {
            uint256 remaining = b.periodFinish - block.timestamp;
            uint256 leftover = remaining * b.rewardRate;
            b.rewardRate = (reward + leftover) / DURATION;
        }
        b.lastUpdateTime = block.timestamp;
        b.periodFinish = block.timestamp + DURATION;
        emit BribeAdded(token, reward);
    }

    function lastTimeBribeApplicable(address token) public view returns (uint256) {
        BribeData storage b = bribes[token];
        return block.timestamp < b.periodFinish ? block.timestamp : b.periodFinish;
    }

    function bribeRewardPerToken(address token) public view returns (uint256) {
        BribeData storage b = bribes[token];
        if (totalBoostedSupply == 0) {
            return b.rewardPerTokenStored;
        }
        return
            b.rewardPerTokenStored +
            ((lastTimeBribeApplicable(token) - b.lastUpdateTime) * b.rewardRate * 1e18) /
            totalBoostedSupply;
    }

    function bribeEarned(address token, address account) public view returns (uint256) {
        BribeData storage b = bribes[token];
        return
            (boostedBalances[account] * (bribeRewardPerToken(token) - b.userRewardPerTokenPaid[account])) /
            1e18 +
            b.rewards[account];
    }

    function _updateBribes(address account) internal {
        for (uint256 i = 0; i < bribeTokens.length; ++i) {
            address token = bribeTokens[i];
            BribeData storage b = bribes[token];
            b.rewardPerTokenStored = bribeRewardPerToken(token);
            b.lastUpdateTime = lastTimeBribeApplicable(token);
            if (account != address(0)) {
                b.rewards[account] = bribeEarned(token, account);
                b.userRewardPerTokenPaid[account] = b.rewardPerTokenStored;
            }
        }
    }
}

