// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IYieldStrategy {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function totalAssets() external view returns (uint256);
    function harvest(uint256 slippageBpsOverride) external returns (uint256);
}

/**
 * @title GPDYieldVault0
 * @dev ERC4626 Vault with strategy, fees, compounding, withdrawal tiering, whitelisting, and event tracking.
 */
contract GPDYieldVault0 is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    IYieldStrategy public strategy;

    IERC20 public immutable twocats;
    IERC20 public immutable gerza;
    IERC20 public immutable pussy;

    address public devAddress;
    uint256 public constant PERFORMANCE_FEE_BPS = 500; // 5%

    mapping(address => uint256) public depositTimestamps;
    mapping(address => bool) public feeExempt;

    event DepositMade(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 fee);
    event Compounded(uint256 harvested, uint256 fee);
    event FeeExemptionUpdated(address indexed user, bool isExempt);

    constructor(
        IERC20 _asset,
        address _twocats,
        address _gerza,
        address _pussy,
        address _dev,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) ERC4626(_asset) {
        twocats = IERC20(_twocats);
        gerza = IERC20(_gerza);
        pussy = IERC20(_pussy);
        devAddress = _dev;
    }

    function setStrategy(address _strategy) external onlyOwner {
        strategy = IYieldStrategy(_strategy);
        IERC20(asset()).safeApprove(address(strategy), 0);
        IERC20(asset()).safeApprove(address(strategy), type(uint256).max);
    }

    function totalAssets() public view override returns (uint256) {
        return strategy.totalAssets();
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        require(assets > 0, "Deposit must be > 0");
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);
        strategy.deposit(assets);
        _mint(receiver, shares);
        depositTimestamps[receiver] = block.timestamp;
        emit DepositMade(receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal override {
        require(shares > 0, "Withdraw must be > 0");

        uint256 feeBps = feeExempt[owner] ? 0 : getWithdrawalFee(owner);
        uint256 fee = (assets * feeBps) / 10000;
        uint256 amountAfterFee = assets - fee;

        _burn(owner, shares);
        strategy.withdraw(assets);

        if (fee > 0) {
            IERC20(asset()).safeTransfer(devAddress, fee);
        }

        IERC20(asset()).safeTransfer(receiver, amountAfterFee);
        emit Withdrawn(receiver, assets, fee);
    }

    function getWithdrawalFee(address user) public view returns (uint256) {
        uint256 timeHeld = block.timestamp - depositTimestamps[user];
        if (timeHeld < 1 weeks) return 1000; // 10%
        if (timeHeld < 2 weeks) return 700;  // 7%
        if (timeHeld < 3 weeks) return 400;  // 4%
        if (timeHeld < 4 weeks) return 200;  // 2%
        return 0;
    }

    function setFeeExempt(address user, bool isExempt) external onlyOwner {
        feeExempt[user] = isExempt;
        emit FeeExemptionUpdated(user, isExempt);
    }

    function depositTWOCATS(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        twocats.safeTransferFrom(msg.sender, address(this), amount);
    }

    function depositGERZA(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        gerza.safeTransferFrom(msg.sender, address(this), amount);
    }

    function depositPUSSY(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be > 0");
        pussy.safeTransferFrom(msg.sender, address(this), amount);
    }

    function compound() external onlyOwner {
        uint256 harvested = strategy.harvest(0);
        if (harvested > 0) {
            uint256 fee = (harvested * PERFORMANCE_FEE_BPS) / 10000;
            IERC20(asset()).safeTransfer(devAddress, fee);
            strategy.deposit(harvested - fee);
            emit Compounded(harvested, fee);
        }
    }

    // Frontend helper
    function timeUntilNoFee(address user) external view returns (uint256) {
        uint256 timeHeld = block.timestamp - depositTimestamps[user];
        if (timeHeld >= 4 weeks) return 0;
        return 4 weeks - timeHeld;
    }
}
