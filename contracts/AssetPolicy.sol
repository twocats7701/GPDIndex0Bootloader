// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IAssetPolicy.sol";

contract AssetPolicy is Ownable, IAssetPolicy {
    struct TradeBand {
        uint256 floorIndex;
        uint256 lowerBound;
        uint256 upperBound;
        bool sellEnabled;
    }

    mapping(address => TradeBand) private bands;
    mapping(address => mapping(address => bool)) private routerWhitelist;

    bool private priceWithinBand = true;
    bool private dexSellsGated = false;
    bool private oracleValid = true;
    uint256 private floor;

    event TradeBandUpdated(address indexed asset, uint256 floorIndex, uint256 lowerBound, uint256 upperBound, bool sellEnabled);
    event RouterWhitelistUpdated(address indexed asset, address indexed router, bool allowed);

    constructor() {
        priceWithinBand = true;
        dexSellsGated = false;
        oracleValid = true;
    }

    function setTradeBand(
        address asset,
        uint256 floorIndex,
        uint256 lowerBound,
        uint256 upperBound,
        bool sellEnabled
    ) external onlyOwner {
        bands[asset] = TradeBand(floorIndex, lowerBound, upperBound, sellEnabled);
        emit TradeBandUpdated(asset, floorIndex, lowerBound, upperBound, sellEnabled);
    }

    function setRouterAllowed(address asset, address router, bool allowed) external onlyOwner {
        routerWhitelist[asset][router] = allowed;
        emit RouterWhitelistUpdated(asset, router, allowed);
    }

    function setPriceWithinBand(bool v) external onlyOwner {
        priceWithinBand = v;
    }

    function setDexSellsGated(bool v) external onlyOwner {
        dexSellsGated = v;
    }

    function setOracleValid(bool v) external onlyOwner {
        oracleValid = v;
    }

    function setFloor(uint256 f) external onlyOwner {
        floor = f;
    }

    function getTradeBand(address asset)
        external
        view
        returns (uint256 floorIndex, uint256 lowerBound, uint256 upperBound, bool sellEnabled)
    {
        TradeBand memory b = bands[asset];
        return (b.floorIndex, b.lowerBound, b.upperBound, b.sellEnabled);
    }

    function isDexSellAllowed(address asset, uint256 price) public view returns (bool) {
        TradeBand storage band = bands[asset];
        if (!band.sellEnabled) return false;
        if (band.lowerBound == 0 && band.upperBound == 0) return true;
        return price >= band.lowerBound && price <= band.upperBound;
    }

    function allowedRouters(address asset, address router) external view returns (bool) {
        return routerWhitelist[asset][router];
    }

    function isPriceWithinBand() external view override returns (bool) {
        return priceWithinBand;
    }

    function areDexSellsGated() external view override returns (bool) {
        return dexSellsGated;
    }

    function isOracleValid() external view override returns (bool) {
        return oracleValid;
    }

    function currentFloor() external view override returns (uint256) {
        return floor;
    }
}

