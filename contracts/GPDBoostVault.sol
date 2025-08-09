// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./GPDYieldVault0.sol"; // for IYieldStrategy interface

interface IVotingEscrow {
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title GPDBoostVault
 * @notice Aggregates TWOCATS and GERZA deposits, stakes them into underlying
 *         strategies and distributes rewards boosted by the vault's veGPINDEX0
 *         balance. Users can query their boost, underlying stake and claim
 *         accrued rewards.
 */
contract GPDBoostVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable twocats;
    IERC20 public immutable gerza;
    IERC20 public immutable rewardToken;
    IVotingEscrow public immutable veToken;

    IYieldStrategy public twocatsStrategy;
    IYieldStrategy public gerzaStrategy;

    address public dao;

    IKeeperSlasher public keeperSlasher;
    ITipVault public tipVault;

    modifier onlyKeeper() {
        require(address(keeperSlasher) != address(0), "slasher not set");
        require(keeperSlasher.isAllowed(msg.sender), "Not keeper");
        _;
        if (address(tipVault) != address(0)) {
            tipVault.claimTipFor(msg.sender);
        }
    }

    modifier onlyGovernance() {
        require(msg.sender == owner() || msg.sender == dao, "Not authorized");
        _;
    }

    struct UserInfo {
        uint256 twocatsUnderlying;
        uint256 gerzaUnderlying;
        uint256 rewardDebt;
    }

    mapping(address => UserInfo) public userInfo;
    mapping(address => uint256) public rewards;

    uint256 public accRewardPerShare; // scaled by 1e12
    uint256 public totalUnderlying;

    bool public autoCompoundEnabled;

    event StrategiesSet(address twocatsStrategy, address gerzaStrategy);
    event Deposited(address indexed user, uint256 twocatsAmount, uint256 gerzaAmount);
    event Withdrawn(address indexed user, uint256 twocatsAmount, uint256 gerzaAmount);
    event RewardClaimed(address indexed user, uint256 amount);
    event Harvest(uint256 amount);

    constructor(
        address _twocats,
        address _gerza,
        address _rewardToken,
        address _veToken
    ) {
        twocats = IERC20(_twocats);
        gerza = IERC20(_gerza);
        rewardToken = IERC20(_rewardToken);
        veToken = IVotingEscrow(_veToken);
    }

    function setDao(address _dao) external onlyOwner {
        require(_dao != address(0), "DAO address cannot be zero");
        dao = _dao;
    }

    function setKeeperAddresses(address _slasher, address _tipVault) external onlyOwner {
        keeperSlasher = IKeeperSlasher(_slasher);
        tipVault = ITipVault(_tipVault);
    }

    function setAutoCompoundEnabled(bool enabled) external onlyOwner {
        autoCompoundEnabled = enabled;
    }

    /**
     * @notice Set the strategies where underlying assets will be staked.
     */
    function setStrategies(address _twocatsStrategy, address _gerzaStrategy) external onlyGovernance {
        twocatsStrategy = IYieldStrategy(_twocatsStrategy);
        gerzaStrategy = IYieldStrategy(_gerzaStrategy);

        if (_twocatsStrategy != address(0)) {
            twocats.safeApprove(_twocatsStrategy, 0);
            twocats.safeApprove(_twocatsStrategy, type(uint256).max);
        }
        if (_gerzaStrategy != address(0)) {
            gerza.safeApprove(_gerzaStrategy, 0);
            gerza.safeApprove(_gerzaStrategy, type(uint256).max);
        }
        emit StrategiesSet(_twocatsStrategy, _gerzaStrategy);
    }

    // ------------------------------------------------------------------
    //                          Internal helpers
    // ------------------------------------------------------------------

    function _updateRewards(address account) internal {
        uint256 reward;
        if (address(twocatsStrategy) != address(0)) {
            reward += twocatsStrategy.harvest(0);
        }
        if (address(gerzaStrategy) != address(0)) {
            reward += gerzaStrategy.harvest(0);
        }
        if (reward > 0 && totalUnderlying > 0) {
            accRewardPerShare += (reward * 1e12) / totalUnderlying;
            emit Harvest(reward);
        }

        if (account != address(0)) {
            UserInfo storage u = userInfo[account];
            uint256 total = u.twocatsUnderlying + u.gerzaUnderlying;
            if (total > 0) {
                uint256 accumulated = (total * accRewardPerShare) / 1e12;
                rewards[account] += accumulated - u.rewardDebt;
                u.rewardDebt = accumulated;
            } else {
                u.rewardDebt = 0;
            }
        }
    }

    function _userTotal(UserInfo storage u) internal view returns (uint256) {
        return u.twocatsUnderlying + u.gerzaUnderlying;
    }

    // ------------------------------------------------------------------
    //                             User actions
    // ------------------------------------------------------------------

    function depositTWOCATS(uint256 amount) external nonReentrant {
        require(amount > 0, "amount=0");
        _updateRewards(msg.sender);
        twocats.safeTransferFrom(msg.sender, address(this), amount);
        twocatsStrategy.deposit(amount);

        UserInfo storage u = userInfo[msg.sender];
        u.twocatsUnderlying += amount;
        totalUnderlying += amount;
        u.rewardDebt = (_userTotal(u) * accRewardPerShare) / 1e12;
        emit Deposited(msg.sender, amount, 0);
        if (autoCompoundEnabled) {
            _compound();
        }
    }

    function depositGERZA(uint256 amount) external nonReentrant {
        require(amount > 0, "amount=0");
        _updateRewards(msg.sender);
        gerza.safeTransferFrom(msg.sender, address(this), amount);
        gerzaStrategy.deposit(amount);

        UserInfo storage u = userInfo[msg.sender];
        u.gerzaUnderlying += amount;
        totalUnderlying += amount;
        u.rewardDebt = (_userTotal(u) * accRewardPerShare) / 1e12;
        emit Deposited(msg.sender, 0, amount);
        if (autoCompoundEnabled) {
            _compound();
        }
    }

    function withdrawTWOCATS(uint256 amount) external nonReentrant {
        UserInfo storage u = userInfo[msg.sender];
        require(u.twocatsUnderlying >= amount, "insufficient");
        _updateRewards(msg.sender);
        u.twocatsUnderlying -= amount;
        totalUnderlying -= amount;
        twocatsStrategy.withdraw(amount);
        twocats.safeTransfer(msg.sender, amount);
        u.rewardDebt = (_userTotal(u) * accRewardPerShare) / 1e12;
        emit Withdrawn(msg.sender, amount, 0);
        if (autoCompoundEnabled) {
            _compound();
        }
    }

    function withdrawGERZA(uint256 amount) external nonReentrant {
        UserInfo storage u = userInfo[msg.sender];
        require(u.gerzaUnderlying >= amount, "insufficient");
        _updateRewards(msg.sender);
        u.gerzaUnderlying -= amount;
        totalUnderlying -= amount;
        gerzaStrategy.withdraw(amount);
        gerza.safeTransfer(msg.sender, amount);
        u.rewardDebt = (_userTotal(u) * accRewardPerShare) / 1e12;
        emit Withdrawn(msg.sender, 0, amount);
        if (autoCompoundEnabled) {
            _compound();
        }
    }

    function claimBoostedRewards() external nonReentrant returns (uint256) {
        _updateRewards(msg.sender);
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardClaimed(msg.sender, reward);
        }
        return reward;
    }

    function compound() external onlyKeeper nonReentrant {
        _compound();
    }

    function harvest() external onlyKeeper nonReentrant {
        _updateRewards(address(0));
    }

    function _compound() internal {
        _updateRewards(address(0));
    }

    // ------------------------------------------------------------------
    //                              Views
    // ------------------------------------------------------------------

    function pendingRewards(address account) external view returns (uint256) {
        UserInfo memory u = userInfo[account];
        uint256 total = u.twocatsUnderlying + u.gerzaUnderlying;
        uint256 accumulated = (total * accRewardPerShare) / 1e12;
        return rewards[account] + accumulated - u.rewardDebt;
    }

    /**
     * @notice Returns the boost multiplier for `user` scaled by 1e18.
     */
    function getBoostPercentage(address user) external view returns (uint256) {
        UserInfo memory u = userInfo[user];
        uint256 userStake = u.twocatsUnderlying + u.gerzaUnderlying;
        if (userStake == 0 || totalUnderlying == 0) {
            return 0;
        }
        uint256 totalVe = veToken.balanceOf(address(this));
        uint256 userVeShare = (totalVe * userStake) / totalUnderlying;
        uint256 boosted = userStake + userVeShare;
        return (boosted * 1e18) / userStake;
    }

    function underlyingStake(address user)
        external
        view
        returns (uint256 twocatsAmount, uint256 gerzaAmount)
    {
        UserInfo memory u = userInfo[user];
        return (u.twocatsUnderlying, u.gerzaUnderlying);
    }
}

