// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Emission Schedule - GPDINDEX0
/// @notice Structured logic for emissions, epochs, and multipliers for vault incentives
contract GPDINDEX0EmissionSchedule is Ownable {
    // Emission token: GPDINDEX0
    address public emissionToken;

    // Emission parameters
    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant EPOCH_DURATION = 30 days;
    uint256 public constant TRANSFER_UNLOCK_PERCENT = 10; // Transfer allowed after 10% emitted

    // Emission logic
    bool public constant EMISSION_STARTS_AFTER_GENESIS = true;
    bool public constant LINEAR_EMISSION = true;
    bool public constant TRANSFER_LOCKED_INITIAL = true;

    // Reward Multipliers by token type
    struct TokenMultiplier {
        string name;
        uint256 multiplierBps; // 1.27x = 12700
    }

    TokenMultiplier[] public tokenMultipliers;

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
        tokenMultipliers.push(TokenMultiplier("TWOCATS", 12700));
        tokenMultipliers.push(TokenMultiplier("GERZA", 11400));
        tokenMultipliers.push(TokenMultiplier("AVAX", 11100));
        tokenMultipliers.push(TokenMultiplier("USDC", 10800));
        tokenMultipliers.push(TokenMultiplier("USDT", 10800));

        daoControls.push("Vault upgrades");
        daoControls.push("Fee exemption whitelists");
        daoControls.push("Strategy allocation changes");
        daoControls.push("DAO voting proposals");
    }

    function setEmissionToken(address _emissionToken) external onlyOwner {
        require(_emissionToken != address(0), "Emission token address cannot be zero");
        emissionToken = _emissionToken;
    }
}

