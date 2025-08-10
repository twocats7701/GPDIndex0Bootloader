// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "./GPDIndex0EmissionSchedule.sol";
import "./AssetPolicy.sol";

interface IPriceOracle {
    function getPrice() external view returns (uint256);
}

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
    function swapExactAVAXForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
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

/// @title GPDIndex0 Bootloader
/// @notice Handles initial bootstrap operations and governance configuration
/// @dev Deploys liquidity, manages emission parameters and governs setup
contract GPDIndex0Bootloader is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Events
    event TokenPurchased(address indexed token, uint256 amount, string dex);
    event LiquidityAdded(address indexed lpToken, address token, uint256 amount, string dex);
    event BootstrapTriggered();
    event TestModeToggled(bool isTestRun);
    event LPWhitelisted(address lpToken);
    event LPUnwhitelisted(address lpToken);
    event BasedChadActivated(address activator);
    event FundsSentToTreasury(address indexed token, uint256 amount, uint256 reasonCode);
    event DepositProcessed(address indexed from, uint256 amount, uint256 invested);
    event ReserveUpdated(uint256 liquidReserve, uint256 investedReserve);
    event SwapExecuted(
        address indexed token,
        uint256 amountIn,
        uint256 amountOut,
        uint256 price,
        uint256 slippageBps
    );
    event LiquidityStaged(
        address indexed token,
        uint256 amountAVAX,
        uint256 amountToken,
        uint256 price,
        uint256 slippageBps
    );
    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);

    IERC20 public twocatsToken;
    IERC20 public gerzaToken;
    IERC20 public pussyToken;
    IERC20 public usdtToken;
    IArenaBondingCurve public twocatsBond;
    IArenaBondingCurve public gerzaBond;
    IRouter public pangolinRouter;
    IRouter public traderJoeRouter;
    IFactory public factory;
    AssetPolicy public assetPolicy;

    uint256 public emissionsPerEpoch;
    uint256 public constant EPOCH_DURATION = 30 days;
    bool public governanceEnabled = false;
    bool public isTestRun = true;
    bool public triggered = false;
    bool public basedChad = false;

    TimelockController public timelock;
    address public governance;
    address public treasury;
    bool public decentralizationInitiated = false;

    uint256 public constant BASED_CHAD_START = 1754611201; // 08 Aug 2025 00:00:01 GMT

    uint256 public targetTVL = 88.8 ether;
    mapping(address => bool) public acceptedLPs;

    uint256 public maxPriceImpactBps = 500; // 5%
    uint256 public maxSlippageBps = 500; // 5%

    mapping(address => bool) public circuitBreakers;
    mapping(address => address) public priceOracles;
    mapping(address => uint256) public marketPrices;
    mapping(address => uint256) public executionPrices;

    uint256 public buyPortionBps = 5000;
    uint256 public minLotSize = 1 ether;
    uint256 public liquidReserve;
    uint256 public investedReserve;

    uint256 public genesisTimestamp;

    modifier onlyGovernance() {
        if (!governanceEnabled &&
            genesisTimestamp > 0 &&
            block.timestamp >= genesisTimestamp + EPOCH_DURATION
        ) {
            governanceEnabled = true;
        }
        require(governanceEnabled, "Governance not enabled");
        if (address(timelock) != address(0)) {
            require(msg.sender == address(timelock), "Not authorized");
        } else {
            require(msg.sender == owner(), "Not authorized");
        }
        _;
    }

    receive() external payable {}
    fallback() external payable {}

    /// @notice Configure token addresses used during bootstrap operations
    /// @param _twocats TWOCATS token address
    /// @param _gerza GERZA token address
    /// @param _pussy PUSSY token address
    /// @param _usdt USDT token address
    function setTokenAddresses(address _twocats, address _gerza, address _pussy, address _usdt) external onlyGovernance {
        require(_twocats != address(0), "TWOCATS token address cannot be zero");
        require(_gerza != address(0), "GERZA token address cannot be zero");
        require(_pussy != address(0), "PUSSY token address cannot be zero");
        require(_usdt != address(0), "USDT token address cannot be zero");
        twocatsToken = IERC20(_twocats);
        gerzaToken = IERC20(_gerza);
        pussyToken = IERC20(_pussy);
        usdtToken = IERC20(_usdt);
    }

    /// @notice Set Arena bonding curve contracts for TWOCATS and GERZA
    /// @param _twocatsBond Address of the TWOCATS bonding contract
    /// @param _gerzaBond Address of the GERZA bonding contract
    function setBondingContracts(address _twocatsBond, address _gerzaBond) external onlyGovernance {
        require(_twocatsBond != address(0), "TWOCATS bond address cannot be zero");
        require(_gerzaBond != address(0), "GERZA bond address cannot be zero");
        twocatsBond = IArenaBondingCurve(_twocatsBond);
        gerzaBond = IArenaBondingCurve(_gerzaBond);
    }

    /// @notice Update router and factory contract addresses
    /// @param _pangolin Pangolin router address
    /// @param _traderJoe TraderJoe router address
    /// @param _factory DEX factory address
    function setRouterAddresses(address _pangolin, address _traderJoe, address _factory) external onlyGovernance {
        require(_pangolin != address(0), "Pangolin router address cannot be zero");
        require(_traderJoe != address(0), "TraderJoe router address cannot be zero");
        require(_factory != address(0), "Factory address cannot be zero");
        pangolinRouter = IRouter(_pangolin);
        traderJoeRouter = IRouter(_traderJoe);
        factory = IFactory(_factory);
    }

    /// @notice Set the asset policy contract
    function setAssetPolicy(address policy) external onlyGovernance {
        assetPolicy = AssetPolicy(policy);
    }

    /// @notice Set number of tokens emitted per epoch
    /// @param _amount Amount of tokens to emit
    function setEmissionsPerEpoch(uint256 _amount) external onlyGovernance {
        require(_amount > 0, "Emissions must be greater than zero");
        emissionsPerEpoch = _amount;
    }

    /// @notice Manually toggle governance capability
    /// @param enabled New governance state
    function setGovernanceEnabled(bool enabled) external onlyOwner {
        governanceEnabled = enabled;
    }

    /// @notice Disable governance within a grace period after genesis
    function rollbackGovernance() external onlyOwner {
        require(
            block.timestamp <
                genesisTimestamp +
                2 * EPOCH_DURATION,
            "Rollback period expired"
        );
        governanceEnabled = false;
    }

    /// @notice Record the timestamp used to compute epochs
    /// @param _genesisTimestamp Genesis timestamp in seconds
    function setGenesisTimestamp(uint256 _genesisTimestamp) external onlyOwner {
        require(_genesisTimestamp > 0, "Genesis timestamp must be > 0");
        genesisTimestamp = _genesisTimestamp;
    }

    /// @notice Return the current epoch number
    function getCurrentEpoch() public view returns (uint256) {
        if (genesisTimestamp == 0 || block.timestamp < genesisTimestamp) {
            return 0;
        }
        return (block.timestamp - genesisTimestamp) / EPOCH_DURATION;
    }

    /// @notice Begin decentralization by setting timelock and governance addresses
    /// @param _timelock Timelock controller address
    /// @param _governance Governance contract address
    function beginDecentralization(address payable _timelock, address _governance) external onlyOwner {
        require(!decentralizationInitiated, "Decentralization already begun");
        require(_timelock != address(0) && _governance != address(0), "Zero address");
        timelock = TimelockController(_timelock);
        address previousGovernance = governance;
        governance = _governance;
        decentralizationInitiated = true;
        transferOwnership(_timelock);
        emit GovernanceTransferred(previousGovernance, _governance);
    }

    /// @notice Enable or disable test mode
    /// @param value True to run in test mode
    function setTestRun(bool value) external onlyOwner {
        isTestRun = value;
        emit TestModeToggled(value);
    }

    /// @notice Set target TVL required before final bootstrap
    /// @param _amountInWei Target in wei
    function setTargetTVL(uint256 _amountInWei) external onlyGovernance {
        require(_amountInWei > 0, "Threshold must be greater than 0");
        targetTVL = _amountInWei;
    }

    /// @notice Set risk parameters for swaps
    /// @param _maxPriceImpactBps Maximum allowed price impact in basis points
    /// @param _maxSlippageBps Maximum allowed slippage in basis points
    function setRiskParams(uint256 _maxPriceImpactBps, uint256 _maxSlippageBps) external onlyGovernance {
        require(_maxPriceImpactBps <= 10000 && _maxSlippageBps <= 10000, "BPS too high");
        maxPriceImpactBps = _maxPriceImpactBps;
        maxSlippageBps = _maxSlippageBps;
    }

    /// @notice Assign oracle address for a token
    function setPriceOracle(address token, address oracle) external onlyGovernance {
        require(token != address(0) && oracle != address(0), "Invalid address");
        priceOracles[token] = oracle;
    }

    /// @notice Set quoted market price for a token (1e18 precision)
    function setMarketPrice(address token, uint256 price) external onlyGovernance {
        marketPrices[token] = price;
    }

    /// @notice Set execution price for a token (1e18 precision)
    function setExecutionPrice(address token, uint256 price) external onlyGovernance {
        executionPrices[token] = price;
    }

    /// @notice Toggle circuit breaker for a token
    function setCircuitBreaker(address token, bool active) external onlyGovernance {
        circuitBreakers[token] = active;
    }

    /// @notice Set portion of deposits routed to investments
    /// @param _bps Basis points of deposit to convert
    function setBuyPortionBps(uint256 _bps) external onlyGovernance {
        require(_bps <= 10000, "BPS too high");
        buyPortionBps = _bps;
    }

    /// @notice Set minimum lot size before conversion
    /// @param _amount Lot size in wei
    function setMinLotSize(uint256 _amount) external onlyGovernance {
        minLotSize = _amount;
    }

    /// @notice Deposit AVAX into the bootloader
    function deposit() external payable nonReentrant {
        require(msg.value > 0, "Amount must be greater than zero");
        liquidReserve += msg.value;

        uint256 totalValue = liquidReserve + investedReserve;
        uint256 desiredInvested = (totalValue * buyPortionBps) / 10000;
        uint256 toInvest = desiredInvested > investedReserve ? desiredInvested - investedReserve : 0;

        if (toInvest >= minLotSize && toInvest <= liquidReserve) {
            _buyAndAddLiquidity(toInvest);
        }

        emit DepositProcessed(msg.sender, msg.value, toInvest);

        if (!triggered && totalValue >= targetTVL) {
            _triggerBootstrap();
        }
    }

    /// @notice Approve an LP token for future operations
    /// @param tokenA First token of the pair
    /// @param tokenB Second token of the pair
    /// @param lp LP token address
    function whitelistLP(address tokenA, address tokenB, address lp) external onlyGovernance {
        require(tokenA != address(0), "Token A address cannot be zero");
        require(tokenB != address(0), "Token B address cannot be zero");
        require(lp != address(0), "LP address cannot be zero");

        address pair = factory.getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");
        require(pair == lp, "LP mismatch");

        acceptedLPs[lp] = true;
        emit LPWhitelisted(lp);
    }

    /// @notice Remove an LP token from the whitelist
    /// @param lp LP token address
    function unwhitelistLP(address lp) external onlyGovernance {
        require(lp != address(0), "LP address cannot be zero");
        acceptedLPs[lp] = false;
        emit LPUnwhitelisted(lp);
    }

    /// @notice Set the treasury contract that will hold protocol funds
    /// @param _treasury Address of the treasury contract
    function setTreasury(address _treasury) external onlyGovernance {
        require(_treasury != address(0), "Treasury address cannot be zero");
        treasury = _treasury;
    }

    /// @notice Withdraw AVAX from the contract to the owner
    /// @param amount Amount of AVAX to withdraw
    /// @param reasonCode Code describing the reason for withdrawal
    function withdrawAVAX(uint256 amount, uint256 reasonCode) external onlyGovernance nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(address(this).balance >= amount, "Insufficient AVAX balance");
        require(treasury != address(0), "Treasury not set");

        (bool success, ) = treasury.call{value: amount}("");
        require(success, "AVAX transfer failed");

        emit FundsSentToTreasury(address(0), amount, reasonCode);
    }

    /// @notice Withdraw an arbitrary ERC20 token to the owner
    /// @param token Token address to withdraw
    /// @param amount Amount of tokens to send
    /// @param reasonCode Code describing the reason for withdrawal
    function withdrawToken(address token, uint256 amount, uint256 reasonCode) external onlyGovernance nonReentrant {
        require(token != address(0), "Token address cannot be zero");
        require(amount > 0, "Amount must be greater than zero");
        require(treasury != address(0), "Treasury not set");

        IERC20(token).safeTransfer(treasury, amount);

        emit FundsSentToTreasury(token, amount, reasonCode);
    }

    /// @notice Anyone can activate the based chad mode once the timestamp is reached
    function activateBasedChad() external nonReentrant {
        require(block.timestamp >= BASED_CHAD_START, "Too early for based chad");
        basedChad = true;
        emit BasedChadActivated(msg.sender);
        _triggerBootstrap();
    }

    /// @notice Return whether bootstrap conditions have been met
    /// @return ready True if bootstrap is complete
    /// @return status Description of current state
    function getBootstrapStatus() public view returns (bool ready, string memory status) {
        if (!triggered && !basedChad) return (false, isTestRun ? "Waiting for test trigger" : "Waiting for admin trigger");

        return (true, "Bootstrap complete");
    }

    /// @notice Manually trigger the bootstrap sequence
    function triggerBootstrap() external onlyOwner nonReentrant {
        require(!basedChad, "BasedChad activated, bootstrap disabled");
        require(liquidReserve + investedReserve >= targetTVL, "TVL below target");
        _triggerBootstrap();
    }

    /// @dev Internal logic performing the bootstrap flow
    function _triggerBootstrap() internal {
        require(!triggered, "Already triggered");

        uint256 amount = liquidReserve;
        if (amount > 0) {
            _buyAndAddLiquidity(amount);
        }

        triggered = true;
        emit BootstrapTriggered();
    }

    /// @dev Convert AVAX reserves into protocol positions
    function _buyAndAddLiquidity(uint256 amount) internal {
        require(amount > 0, "Amount must be greater than zero");
        require(liquidReserve >= amount, "Insufficient reserve");

        liquidReserve -= amount;
        investedReserve += amount;

        if (address(twocatsToken) != address(0)) {
            uint256 spent = _executeSwap(address(twocatsToken), amount);
            if (spent < amount) {
                uint256 refund = amount - spent;
                liquidReserve += refund;
                investedReserve -= refund;
            }
        }

        emit ReserveUpdated(liquidReserve, investedReserve);
    }

    function _executeSwap(address token, uint256 amountIn) internal returns (uint256 avaxSpent) {
        require(!circuitBreakers[token], "Circuit breaker active");
        require(address(pangolinRouter) != address(0), "Router not set");

        uint256 half = amountIn / 2;
        (uint256 expectedOut, uint256 marketPrice) = _quote(token, half);
        avaxSpent = _swapAndAddLiquidity(token, half, expectedOut, marketPrice);
    }

    function _quote(address token, uint256 amount) internal view returns (uint256 expectedOut, uint256 marketPrice) {
        address oracle = priceOracles[token];
        require(oracle != address(0), "Oracle not set");
        address[] memory path = new address[](2);
        path[0] = pangolinRouter.WAVAX();
        path[1] = token;
        expectedOut = pangolinRouter.getAmountsOut(amount, path)[1];
        uint256 oraclePrice = IPriceOracle(oracle).getPrice();
        marketPrice = (amount * 1e18) / expectedOut;
        uint256 priceImpact = marketPrice > oraclePrice
            ? (marketPrice - oraclePrice) * 10000 / oraclePrice
            : (oraclePrice - marketPrice) * 10000 / oraclePrice;
        require(priceImpact <= maxPriceImpactBps, "Price impact too high");
    }

    function _swapAndAddLiquidity(
        address token,
        uint256 half,
        uint256 expectedOut,
        uint256 marketPrice
    ) internal returns (uint256 avaxSpent) {
        if (address(assetPolicy) != address(0)) {
            address wavax = pangolinRouter.WAVAX();
            uint256 price = (expectedOut * 1e18) / half;
            require(assetPolicy.allowedRouters(wavax, address(pangolinRouter)), "ROUTER_NOT_ALLOWED");
            require(assetPolicy.isDexSellAllowed(wavax, price), "SELL_NOT_ALLOWED");
        }
        uint256 amountOut = pangolinRouter.swapExactAVAXForTokens{value: half}(
            0,
            _buildPath(token),
            address(this),
            block.timestamp
        )[1];

        uint256 execPrice = (half * 1e18) / amountOut;
        uint256 slippage = execPrice > marketPrice
            ? (execPrice - marketPrice) * 10000 / marketPrice
            : (marketPrice - execPrice) * 10000 / marketPrice;
        require(slippage <= maxSlippageBps, "Slippage too high");

        IERC20(token).safeApprove(address(pangolinRouter), 0);
        IERC20(token).safeApprove(address(pangolinRouter), amountOut);
        (uint256 usedToken, uint256 usedAVAX, ) = pangolinRouter.addLiquidityAVAX{value: half}(
            token,
            amountOut,
            (amountOut * (10000 - maxSlippageBps)) / 10000,
            (half * (10000 - maxSlippageBps)) / 10000,
            address(this),
            block.timestamp
        );

        avaxSpent = half + usedAVAX;

        emit SwapExecuted(token, half, amountOut, execPrice, slippage);
        emit LiquidityStaged(token, usedAVAX, usedToken, execPrice, slippage);
    }

    function _buildPath(address token) internal view returns (address[] memory path) {
        path = new address[](2);
        path[0] = pangolinRouter.WAVAX();
        path[1] = token;
    }
}
