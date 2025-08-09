// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DAOTreasury
 * @notice Treasury controlled by DAO and its operators to fund tip vaults and reward escrows.
 */
contract DAOTreasury {
    using SafeERC20 for IERC20;

    address public dao;
    mapping(address => bool) public operators;

    event OperatorUpdated(address indexed operator, bool active);
    event FundsWithdrawn(address indexed operator, address indexed token, address indexed to, uint256 amount);
    event TipVaultFunded(address indexed operator, address indexed tipVault, uint256 amount);
    event RewardEscrowFunded(address indexed operator, address indexed escrow, uint256 amount);

    modifier onlyDAO() {
        require(msg.sender == dao, "Not DAO");
        _;
    }

    modifier onlyOperator() {
        require(operators[msg.sender], "Not operator");
        _;
    }

    constructor(address _dao) {
        dao = _dao;
        operators[_dao] = true;
    }

    function setOperator(address op, bool active) external onlyDAO {
        operators[op] = active;
        emit OperatorUpdated(op, active);
    }

    function withdraw(IERC20 token, address to, uint256 amount) external onlyOperator {
        token.safeTransfer(to, amount);
        emit FundsWithdrawn(msg.sender, address(token), to, amount);
    }

    function fundTipVault(IERC20 token, address tipVault, uint256 amount) external onlyOperator {
        token.safeTransfer(tipVault, amount);
        emit TipVaultFunded(msg.sender, tipVault, amount);
    }

    function fundRewardEscrow(IERC20 token, address escrow, uint256 amount) external onlyOperator {
        token.safeTransfer(escrow, amount);
        emit RewardEscrowFunded(msg.sender, escrow, amount);
    }
}

