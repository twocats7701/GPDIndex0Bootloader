// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAssetPolicy {
    function isPriceWithinBand() external view returns (bool);
    function areDexSellsGated() external view returns (bool);
    function isOracleValid() external view returns (bool);
    function currentFloor() external view returns (uint256);
}

