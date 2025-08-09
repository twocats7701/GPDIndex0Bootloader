// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Emission Schedule - GPDIndex0
/// @notice Stores emission constants and exposes ve based governance weight
///         calculations.  Token weighting is dynamic so that powerful assets
///         such as TWOCATS and GERZA can be given additional governance power
///         while still allowing future re-weighting or new asset inclusion.
interface IVeToken {
    function balanceOf(address account) external view returns (uint256);
}

contract GPDIndex0EmissionSchedule is Ownable {
    // ---------------------------------------------------------------------
    //                          Governance control
    // ---------------------------------------------------------------------

    address public dao;
    bool public governanceEnabled;
    uint256 public genesisTimestamp;

    modifier onlyGovernance() {
        if (
            !governanceEnabled &&
            genesisTimestamp > 0 &&
            block.timestamp >= genesisTimestamp + EPOCH_DURATION
        ) {
            governanceEnabled = true;
        }
        require(governanceEnabled, "Governance not enabled");
        require(msg.sender == owner() || msg.sender == dao, "Not authorized");
        _;
    }
    // ---------------------------------------------------------------------
    //                         Emission parameters
    // ---------------------------------------------------------------------

    address public emissionToken; // Emission token: GPDIndex0

    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant EPOCH_DURATION = 30 days;
    uint256 public constant TRANSFER_UNLOCK_PERCENT = 10; // Transfer allowed after 10% emitted

    bool public constant EMISSION_STARTS_AFTER_GENESIS = true;
    bool public constant LINEAR_EMISSION = true;
    bool public constant TRANSFER_LOCKED_INITIAL = true;

    // ---------------------------------------------------------------------
    //                       Governance token weighting
    // ---------------------------------------------------------------------

    // token => multiplier in basis points (10_000 = 1x, 15_000 = 1.5x)
    mapping(address => uint256) public tokenWeightBps;
    address[] public weightTokens;

    event TokenWeightSet(address indexed token, uint256 weightBps);
    event TokenWeightRemoved(address indexed token);

    // Early AVAX depositor global bonus
    uint256 public constant EARLY_AVAX_GLOBAL_BONUS_BPS = 12800;

    // Governance token usage
    bool public constant GOVERNANCE_ENABLED = true;
    string public constant GOVERNANCE_TOKEN = "GPDINDEX0";

    // Governance actions
    string[] public daoControls;

    // Future epochs supported
    bool public constant FUTURE_EPOCHS_ENABLED = true;
    string public constant FUTURE_TOKEN_PATTERN = "GPDINDEX[n]";

    constructor() {
        // Default weighting for core assets.  Addresses are expected to be
        // provided post-deployment via `setTokenWeight` but the typical
        // multipliers are documented here for reference.
        // TWOCATS => 1.5x (15_000 bps)
        // GERZA   => 1.27x (12_700 bps)

        daoControls.push("Vault upgrades");
        daoControls.push("Fee exemption whitelists");
        daoControls.push("Strategy allocation changes");
        daoControls.push("DAO voting proposals");
    }

    function setGovernanceEnabled(bool enabled) external onlyOwner {
        governanceEnabled = enabled;
    }

    function rollbackGovernance() external onlyOwner {
        require(
            block.timestamp < genesisTimestamp + 2 * EPOCH_DURATION,
            "Rollback period expired"
        );
        governanceEnabled = false;
    }

    function setGenesisTimestamp(uint256 _genesisTimestamp) external onlyOwner {
        require(_genesisTimestamp > 0, "Genesis timestamp must be > 0");
        genesisTimestamp = _genesisTimestamp;
    }

    function setDao(address _dao) external onlyOwner {
        require(_dao != address(0), "DAO address cannot be zero");
        dao = _dao;
    }

    /// @notice Assign or update weighting for a ve token.
    /// @dev `weightBps` uses basis points. For example 12_700 represents 1.27x.
    function setTokenWeight(address token, uint256 weightBps) external onlyGovernance {
        require(token != address(0), "Token address cannot be zero");
        require(weightBps > 0, "Weight must be > 0");

        if (tokenWeightBps[token] == 0) {
            weightTokens.push(token);
        }
        tokenWeightBps[token] = weightBps;
        emit TokenWeightSet(token, weightBps);
    }

    /// @notice Remove a token from weighting consideration.
    function removeTokenWeight(address token) external onlyGovernance {
        require(tokenWeightBps[token] != 0, "Token not set");
        delete tokenWeightBps[token];

        uint256 len = weightTokens.length;
        for (uint256 i = 0; i < len; i++) {
            if (weightTokens[i] == token) {
                weightTokens[i] = weightTokens[len - 1];
                weightTokens.pop();
                break;
            }
        }
        emit TokenWeightRemoved(token);
    }

    /// @notice Returns the aggregated governance weight for `user`.
    /// @dev Iterates over all tracked tokens and sums the weighted ve balance.
    function getGovernanceWeight(address user) external view returns (uint256 totalWeight) {
        uint256 len = weightTokens.length;
        for (uint256 i = 0; i < len; i++) {
            address token = weightTokens[i];
            uint256 weight = tokenWeightBps[token];
            if (weight == 0) continue;
            uint256 bal = IVeToken(token).balanceOf(user);
            totalWeight += bal * weight / 10_000;
        }
    }

    /// @notice Sets the address of the token being emitted (GPDINDEX0).
    function setEmissionToken(address _emissionToken) external onlyGovernance {
        require(_emissionToken != address(0), "Emission token address cannot be zero");
        emissionToken = _emissionToken;
    }
}

