// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IAssetPolicy.sol";

contract MockAssetPolicy is IAssetPolicy {
    bool public priceWithinBand = true;
    bool public dexSellsGated = false;
    bool public oracleValid = true;
    uint256 public floor = 0;

    function setPriceWithinBand(bool v) external { priceWithinBand = v; }
    function setDexSellsGated(bool v) external { dexSellsGated = v; }
    function setOracleValid(bool v) external { oracleValid = v; }
    function setFloor(uint256 f) external { floor = f; }

    function isPriceWithinBand() external view override returns (bool) { return priceWithinBand; }
    function areDexSellsGated() external view override returns (bool) { return dexSellsGated; }
    function isOracleValid() external view override returns (bool) { return oracleValid; }
    function currentFloor() external view override returns (uint256) { return floor; }

    function getTradeBand(address /*asset*/)
        external
        pure
        returns (uint256 floorIndex, uint256 lowerBound, uint256 upperBound, bool sellEnabled)
    {
        return (0, 0, 0, true);
    }

    function isDexSellAllowed(address /*asset*/, uint256 /*price*/) external pure returns (bool) {
        return true;
    }

    function allowedRouters(address /*asset*/, address /*router*/) external pure returns (bool) {
        return true;
    }
}
