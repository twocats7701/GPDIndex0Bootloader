// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IKeeperSlasher {
    function isAllowed(address keeper) external view returns (bool);
}

/**
 * @title TipVault
 * @notice Generic tip vault paying registered keepers for upkeep.
 */
contract TipVault {
    using SafeERC20 for IERC20;

    address public owner;
    IERC20 public immutable tipToken;
    uint256 public tipAmount;
    uint256 public cooldown;
    IKeeperSlasher public slasher;

    mapping(address => uint256) public lastClaimedBy;

    event TipClaimed(address indexed keeper, uint256 amount);
    event TipFunded(address indexed funder, uint256 amount);
    event TipUpdated(uint256 newTipAmount, uint256 cooldownPeriod);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _token, uint256 _tipAmount, uint256 _cooldown, address _slasher) {
        owner = msg.sender;
        tipToken = IERC20(_token);
        tipAmount = _tipAmount;
        cooldown = _cooldown;
        slasher = IKeeperSlasher(_slasher);
    }

    function fundTips(uint256 amount) external {
        tipToken.safeTransferFrom(msg.sender, address(this), amount);
        emit TipFunded(msg.sender, amount);
    }

    function claimTip() external {
        claimTipFor(msg.sender);
    }

    function claimTipFor(address keeper) public {
        require(slasher.isAllowed(keeper), "Not allowed");
        require(block.timestamp - lastClaimedBy[keeper] >= cooldown, "Cooldown active");
        lastClaimedBy[keeper] = block.timestamp;
        tipToken.safeTransfer(keeper, tipAmount);
        emit TipClaimed(keeper, tipAmount);
    }

    function updateTipAmount(uint256 newTip, uint256 newCooldown) external onlyOwner {
        tipAmount = newTip;
        cooldown = newCooldown;
        emit TipUpdated(newTip, newCooldown);
    }
}

