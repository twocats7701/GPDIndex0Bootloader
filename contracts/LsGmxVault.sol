// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./GmxStakingStrategy.sol";

/**
 * @title LsGmxVault
 * @notice ERC4626 vault accepting GMX and staking via GmxStakingStrategy.
 *         Harvested rewards increase price-per-share without rebasing supply.
 *         Optional performance and management fees can be configured by the owner.
 */
contract LsGmxVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    GmxStakingStrategy public strategy;
    address public devAddress;
    uint256 public performanceFeeBps; // fee on harvested rewards
    uint256 public managementFeeBps;  // fee on total assets during harvest
    bool public autoCompoundEnabled;

    event FeesUpdated(uint256 performanceFeeBps, uint256 managementFeeBps);
    event StrategyUpdated(address strategy);
    event Compounded(uint256 harvested, uint256 fee);

    constructor(
        IERC20 gmx,
        address _dev,
        address _strategy,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC4626(gmx) {
        devAddress = _dev;
        setStrategy(_strategy);
    }

    function setStrategy(address _strategy) public onlyOwner {
        require(_strategy != address(0), "Invalid strategy");
        if (address(strategy) != address(0)) {
            IERC20(asset()).safeApprove(address(strategy), 0);
        }
        strategy = GmxStakingStrategy(_strategy);
        IERC20(asset()).safeApprove(_strategy, type(uint256).max);
        emit StrategyUpdated(_strategy);
    }

    function setFees(uint256 _performanceFeeBps, uint256 _managementFeeBps) external onlyOwner {
        require(_performanceFeeBps <= 2000, "perf too high");
        require(_managementFeeBps <= 1000, "mgmt too high");
        performanceFeeBps = _performanceFeeBps;
        managementFeeBps = _managementFeeBps;
        emit FeesUpdated(_performanceFeeBps, _managementFeeBps);
    }

    function setAutoCompoundEnabled(bool enabled) external onlyOwner {
        autoCompoundEnabled = enabled;
    }

    function totalAssets() public view override returns (uint256) {
        return strategy.totalAssets();
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        shares = super.deposit(assets, receiver);
        if (autoCompoundEnabled) {
            _compound();
        }
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        shares = super.withdraw(assets, receiver, owner);
        if (autoCompoundEnabled) {
            _compound();
        }
    }

    function _deposit(address, address receiver, uint256 assets, uint256 shares) internal override {
        require(assets > 0, "deposit=0");
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        strategy.deposit(assets);
        _mint(receiver, shares);
    }

    function _withdraw(address, address receiver, address owner, uint256 assets, uint256 shares) internal override {
        require(shares > 0, "withdraw=0");
        _burn(owner, shares);
        strategy.withdraw(assets);
        IERC20(asset()).safeTransfer(receiver, assets);
    }

    function compound() external onlyOwner nonReentrant {
        _compound();
    }

    function _compound() internal {
        uint256 harvested = strategy.harvest(0);
        uint256 fee;

        if (managementFeeBps > 0) {
            uint256 mgmt = (strategy.totalAssets() * managementFeeBps) / 10000;
            if (mgmt > 0) {
                strategy.withdraw(mgmt);
                IERC20(asset()).safeTransfer(devAddress, mgmt);
                fee += mgmt;
            }
        }

        if (harvested > 0) {
            uint256 perf = (harvested * performanceFeeBps) / 10000;
            if (perf > 0) {
                IERC20(asset()).safeTransfer(devAddress, perf);
                fee += perf;
                harvested -= perf;
            }
            strategy.deposit(harvested);
        }

        emit Compounded(harvested, fee);
    }
}

