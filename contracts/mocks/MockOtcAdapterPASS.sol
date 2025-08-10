// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IOtcAdapterPASS.sol";

contract MockOtcAdapterPASS is IOtcAdapterPASS {
    address public lastAsset;
    uint256 public lastAmount;
    address public lastReceiver;

    function sell(address asset, uint256 amount, address receiver) external override {
        lastAsset = asset;
        lastAmount = amount;
        lastReceiver = receiver;
        IERC20(asset).transferFrom(msg.sender, receiver, amount);
    }
}
