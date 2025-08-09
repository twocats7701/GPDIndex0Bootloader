// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./keeper/KeeperSlasher.sol";
import "./LsGmxVault.sol";
import "./GmxStakingStrategy.sol";

/**
 * @title GmxHarvester
 * @notice Coordinates reward harvesting for multiple lsGMX vaults. Execution
 *         is gated by the KeeperSlasher contract so only approved keepers can
 *         trigger harvests. Rewards are claimed from the underlying
 *         GmxStakingStrategy and restaked via the owning LsGmxVault.
 */
contract GmxHarvester is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    KeeperSlasher public immutable keeperSlasher;
    EnumerableSet.AddressSet private vaults;

    event VaultAdded(address indexed vault);
    event VaultRemoved(address indexed vault);
    event Harvested(address indexed vault, uint256 rewards);

    constructor(address _keeperSlasher) {
        keeperSlasher = KeeperSlasher(_keeperSlasher);
    }

    modifier onlyKeeper() {
        require(keeperSlasher.isAllowed(msg.sender), "Not keeper");
        _;
    }

    function addVault(address vault) external onlyOwner {
        require(vaults.add(vault), "exists");
        emit VaultAdded(vault);
    }

    function removeVault(address vault) external onlyOwner {
        require(vaults.remove(vault), "missing");
        emit VaultRemoved(vault);
    }

    function vaultCount() external view returns (uint256) {
        return vaults.length();
    }

    /// @notice Harvest rewards for all tracked vaults
    function harvestAll() external onlyKeeper {
        uint256 length = vaults.length();
        for (uint256 i = 0; i < length; i++) {
            _harvestVault(vaults.at(i));
        }
    }

    /// @notice Harvest a single vault by address
    function harvest(address vault) external onlyKeeper {
        require(vaults.contains(vault), "not tracked");
        _harvestVault(vault);
    }

    function _harvestVault(address vaultAddr) internal {
        LsGmxVault vault = LsGmxVault(vaultAddr);
        GmxStakingStrategy strat = vault.strategy();
        uint256 rewards = strat.stakedGmxTracker().claimable(address(strat));
        vault.compound();
        emit Harvested(vaultAddr, rewards);
    }
}

