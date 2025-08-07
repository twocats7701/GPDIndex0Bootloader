// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IRouter {
    function WAVAX() external view returns (address);
    function addLiquidityAVAX(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountAVAXMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountAVAX, uint liquidity);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IArenaBondingCurve {
    function buy() external payable;
    function token() external view returns (address);
    function calculateBuyPrice(uint256 amount) external view returns (uint256);
}

interface IFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function getPairCreator(address pair) external view returns (address);
}

contract GPDIndex0Bootloader is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Events
    event TokenPurchased(address indexed token, uint256 amount, string dex);
    event LiquidityAdded(address indexed lpToken, address token, uint256 amount, string dex);
    event LPCreated(string pair);
    event BootstrapTriggered();
    event TestModeToggled(bool isTestRun);
    event LPWhitelisted(address lpToken);
    event BasedChadActivated(address activator);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    IERC20 public twocatsToken;
    IERC20 public gerzaToken;
    IERC20 public pussyToken;
    IERC20 public usdtToken;
    IArenaBondingCurve public twocatsBond;
    IArenaBondingCurve public gerzaBond;
    IRouter public pangolinRouter;
    IRouter public traderJoeRouter;
    IFactory public factory;

    uint256 public emissionsPerEpoch;
    address public owner;
    bool public governanceEnabled = false;
    bool public isTestRun = true;
    bool public triggered = false;
    bool public basedChad = false;

    uint256 public bootstrapThreshold = 88.8 ether;
    mapping(address => bool) public acceptedLPs;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {}
    fallback() external payable {}

    function setTokenAddresses(address _twocats, address _gerza, address _pussy, address _usdt) external onlyOwner {
        twocatsToken = IERC20(_twocats);
        gerzaToken = IERC20(_gerza);
        pussyToken = IERC20(_pussy);
        usdtToken = IERC20(_usdt);
    }

    function setBondingContracts(address _twocatsBond, address _gerzaBond) external onlyOwner {
        twocatsBond = IArenaBondingCurve(_twocatsBond);
        gerzaBond = IArenaBondingCurve(_gerzaBond);
    }

    function setRouterAddresses(address _pangolin, address _traderJoe, address _factory) external onlyOwner {
        pangolinRouter = IRouter(_pangolin);
        traderJoeRouter = IRouter(_traderJoe);
        factory = IFactory(_factory);
    }

    function setEmissionsPerEpoch(uint256 _amount) external onlyOwner {
        emissionsPerEpoch = _amount;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function setGovernanceEnabled(bool enabled) external onlyOwner {
        governanceEnabled = enabled;
    }

    function setTestRun(bool value) external onlyOwner {
        isTestRun = value;
        emit TestModeToggled(value);
    }

    function setBootstrapThreshold(uint256 _amountInWei) external onlyOwner {
        require(_amountInWei > 0, "Threshold must be greater than 0");
        bootstrapThreshold = _amountInWei;
    }

    function whitelistLP(address lp) external {
        require(governanceEnabled || msg.sender == owner, "Not authorized");
        acceptedLPs[lp] = true;
        emit LPWhitelisted(lp);
    }

    function activateBasedChad() external nonReentrant {
        require(block.timestamp >= 1754611201, "Too early for based chad"); // 08 08 2025 00:00:01 GMT
        basedChad = true;
        emit BasedChadActivated(msg.sender);
        _triggerBootstrap();
    }

    function getBootstrapStatus() public view returns (bool ready, string memory status) {
        if (!triggered && !basedChad) return (false, isTestRun ? "Waiting for test trigger" : "Waiting for admin trigger");

        address twocatsAvaxLP = factory.getPair(address(twocatsToken), pangolinRouter.WAVAX());
        address gerzaAvaxLP = factory.getPair(address(gerzaToken), pangolinRouter.WAVAX());

        bool assetsBought = twocatsAvaxLP != address(0) && gerzaAvaxLP != address(0);
        bool lpsWhitelisted = acceptedLPs[twocatsAvaxLP] && acceptedLPs[gerzaAvaxLP];

        if (assetsBought && lpsWhitelisted) return (true, "Bootstrap complete and LPs accepted");
        return (false, "Bootstrap incomplete or LPs not verified");
    }

    function triggerBootstrap() external onlyOwner nonReentrant {
        require(!basedChad, "BasedChad activated, bootstrap disabled");
        _triggerBootstrap();
    }

    function _triggerBootstrap() internal {
        require(!triggered, "Already triggered");
        require(
            address(this).balance >= bootstrapThreshold,
            "Balance below bootstrap threshold"
        );

        triggered = true;
        emit BootstrapTriggered();

        uint256 gasReserve = address(this).balance * 5 / 100;
        uint256 amountToUse = address(this).balance - gasReserve;
        uint256 avaxPerToken = amountToUse / 2;

        try twocatsBond.buy{value: avaxPerToken}() {
            emit TokenPurchased(address(twocatsToken), avaxPerToken, "Arena");
        } catch {
            revert("TWOCATS buy failed");
        }

        try gerzaBond.buy{value: avaxPerToken}() {
            emit TokenPurchased(address(gerzaToken), avaxPerToken, "Arena");
        } catch {
            revert("GERZA buy failed");
        }

        address wavax = pangolinRouter.WAVAX();
        uint256 twocatsBalance = twocatsToken.balanceOf(address(this));
        uint256 gerzaBalance = gerzaToken.balanceOf(address(this));

        IERC20(address(twocatsToken)).safeApprove(address(pangolinRouter), 0);
        IERC20(address(twocatsToken)).safeIncreaseAllowance(address(pangolinRouter), twocatsBalance);
        IERC20(address(gerzaToken)).safeApprove(address(pangolinRouter), 0);
        IERC20(address(gerzaToken)).safeIncreaseAllowance(address(pangolinRouter), gerzaBalance);

        try pangolinRouter.addLiquidityAVAX{value: avaxPerToken}(
            address(twocatsToken),
            twocatsBalance,
            1,
            1,
            address(this),
            block.timestamp + 1200
        ) returns (uint, uint, uint liquidity1) {
            address twocatsLP = factory.getPair(address(twocatsToken), wavax);
            acceptedLPs[twocatsLP] = true;
            emit LiquidityAdded(twocatsLP, address(twocatsToken), liquidity1, "Pangolin");
        } catch {
            revert("TWOCATS LP creation failed");
        }

        try pangolinRouter.addLiquidityAVAX{value: avaxPerToken}(
            address(gerzaToken),
            gerzaBalance,
            1,
            1,
            address(this),
            block.timestamp + 1200
        ) returns (uint, uint, uint liquidity2) {
            address gerzaLP = factory.getPair(address(gerzaToken), wavax);
            acceptedLPs[gerzaLP] = true;
            emit LiquidityAdded(gerzaLP, address(gerzaToken), liquidity2, "Pangolin");
        } catch {
            revert("GERZA LP creation failed");
        }
    }
}
