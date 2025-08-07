// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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
    function buy(uint256 minAmountOut) external payable;
    function token() external view returns (address);
    function calculateBuyPrice(uint256 amount) external view returns (uint256);
}

interface IFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function getPairCreator(address pair) external view returns (address);
}

contract GPDIndex0Bootloader is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Events
    event TokenPurchased(address indexed token, uint256 amount, string dex);
    event LiquidityAdded(address indexed lpToken, address token, uint256 amount, string dex);
    event LPCreated(string pair);
    event BootstrapTriggered();
    event TestModeToggled(bool isTestRun);
    event LPWhitelisted(address lpToken);
    event LPUnwhitelisted(address lpToken);
    event BasedChadActivated(address activator);
    event FundsWithdrawn(address indexed token, uint256 amount);

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
    bool public governanceEnabled = false;
    bool public isTestRun = true;
    bool public triggered = false;
    bool public basedChad = false;

    uint256 public bootstrapThreshold = 88.8 ether;
    mapping(address => bool) public acceptedLPs;

    uint256 public buySlippageBps = 9500;
    uint256 public liquiditySlippageBps = 9500;


    receive() external payable {}
    fallback() external payable {}

    function setTokenAddresses(address _twocats, address _gerza, address _pussy, address _usdt) external onlyOwner {
        require(_twocats != address(0), "TWOCATS token address cannot be zero");
        require(_gerza != address(0), "GERZA token address cannot be zero");
        require(_pussy != address(0), "PUSSY token address cannot be zero");
        require(_usdt != address(0), "USDT token address cannot be zero");
        twocatsToken = IERC20(_twocats);
        gerzaToken = IERC20(_gerza);
        pussyToken = IERC20(_pussy);
        usdtToken = IERC20(_usdt);
    }

    function setBondingContracts(address _twocatsBond, address _gerzaBond) external onlyOwner {
        require(_twocatsBond != address(0), "TWOCATS bond address cannot be zero");
        require(_gerzaBond != address(0), "GERZA bond address cannot be zero");
        twocatsBond = IArenaBondingCurve(_twocatsBond);
        gerzaBond = IArenaBondingCurve(_gerzaBond);
    }

    function setRouterAddresses(address _pangolin, address _traderJoe, address _factory) external onlyOwner {
        require(_pangolin != address(0), "Pangolin router address cannot be zero");
        require(_traderJoe != address(0), "TraderJoe router address cannot be zero");
        require(_factory != address(0), "Factory address cannot be zero");
        pangolinRouter = IRouter(_pangolin);
        traderJoeRouter = IRouter(_traderJoe);
        factory = IFactory(_factory);
    }

    function setEmissionsPerEpoch(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Emissions must be greater than zero");
        emissionsPerEpoch = _amount;
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

    function setSlippageBps(uint256 _buySlippageBps, uint256 _liquiditySlippageBps) external onlyOwner {
        require(_buySlippageBps <= 10000 && _liquiditySlippageBps <= 10000, "BPS too high");
        buySlippageBps = _buySlippageBps;
        liquiditySlippageBps = _liquiditySlippageBps;
    }

    function whitelistLP(address tokenA, address tokenB, address lp) external {
        require(governanceEnabled || msg.sender == owner(), "Not authorized");
        require(factory.getPair(tokenA, tokenB) == lp, "LP mismatch");
        acceptedLPs[lp] = true;
        emit LPWhitelisted(lp);
    }

    function unwhitelistLP(address lp) external {
        require(governanceEnabled || msg.sender == owner(), "Not authorized");
        acceptedLPs[lp] = false;
        emit LPUnwhitelisted(lp);
    }

    function withdrawAVAX(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(address(this).balance >= amount, "Insufficient AVAX balance");

        (bool success, ) = owner().call{value: amount}("");
        require(success, "AVAX transfer failed");

        emit FundsWithdrawn(address(0), amount);
    }

    function withdrawToken(address token, uint256 amount) external onlyOwner nonReentrant {
        require(token != address(0), "Token address cannot be zero");
        require(amount > 0, "Amount must be greater than zero");

        IERC20(token).safeTransfer(owner(), amount);

        emit FundsWithdrawn(token, amount);
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
        require(address(twocatsBond) != address(0), "TWOCATS bond not set");
        require(address(gerzaBond) != address(0), "GERZA bond not set");
        require(address(pangolinRouter) != address(0), "Pangolin router not set");
        require(address(factory) != address(0), "Factory not set");
        require(address(twocatsToken) != address(0), "TWOCATS token not set");
        require(address(gerzaToken) != address(0), "GERZA token not set");

        require(!triggered, "Already triggered");
        require(
            address(this).balance >= bootstrapThreshold,
            "Balance below bootstrap threshold"
        );

        triggered = true;
        emit BootstrapTriggered();

        uint256 gasReserve = address(this).balance * 5 / 100;
        uint256 totalToUse = address(this).balance - gasReserve;

        uint256 buyReserve = totalToUse / 2;
        uint256 liquidityReserve = totalToUse - buyReserve;

        uint256 avaxPerBuy = buyReserve / 2;
        uint256 avaxPerLiquidity = liquidityReserve / 2;

        uint256 twocatsMinOut = twocatsBond.calculateBuyPrice(avaxPerBuy) * buySlippageBps / 10000;
        uint256 gerzaMinOut = gerzaBond.calculateBuyPrice(avaxPerBuy) * buySlippageBps / 10000;

        try twocatsBond.buy{value: avaxPerBuy}(twocatsMinOut) {
            emit TokenPurchased(address(twocatsToken), avaxPerBuy, "Arena");
        } catch {
            revert("TWOCATS buy failed");
        }

        try gerzaBond.buy{value: avaxPerBuy}(gerzaMinOut) {
            emit TokenPurchased(address(gerzaToken), avaxPerBuy, "Arena");
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

        uint256 avaxMin = avaxPerLiquidity * liquiditySlippageBps / 10000;

        address[] memory twocatsPath = new address[](2);
        twocatsPath[0] = wavax;
        twocatsPath[1] = address(twocatsToken);
        uint256 twocatsTokenMin = pangolinRouter.getAmountsOut(avaxPerLiquidity, twocatsPath)[1] * liquiditySlippageBps / 10000;

        try pangolinRouter.addLiquidityAVAX{value: avaxPerLiquidity}(
            address(twocatsToken),
            twocatsBalance,
            twocatsTokenMin,
            avaxMin,
            address(this),
            block.timestamp + 1200
        ) returns (uint, uint, uint liquidity1) {
            address twocatsLP = factory.getPair(address(twocatsToken), wavax);
            acceptedLPs[twocatsLP] = true;
            emit LiquidityAdded(twocatsLP, address(twocatsToken), liquidity1, "Pangolin");
        } catch {
            revert("TWOCATS LP creation failed");
        }

        address[] memory gerzaPath = new address[](2);
        gerzaPath[0] = wavax;
        gerzaPath[1] = address(gerzaToken);
        uint256 gerzaTokenMin = pangolinRouter.getAmountsOut(avaxPerLiquidity, gerzaPath)[1] * liquiditySlippageBps / 10000;

        try pangolinRouter.addLiquidityAVAX{value: avaxPerLiquidity}(
            address(gerzaToken),
            gerzaBalance,
            gerzaTokenMin,
            avaxMin,
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
