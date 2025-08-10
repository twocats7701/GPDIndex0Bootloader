// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockFloor {
    uint256 public floorIndex;
    uint256 public price;
    bool public isSelling;
    int256 public netInflowToNextFloor;

    function set(
        uint256 _floorIndex,
        uint256 _price,
        bool _isSelling,
        int256 _netInflow
    ) external {
        floorIndex = _floorIndex;
        price = _price;
        isSelling = _isSelling;
        netInflowToNextFloor = _netInflow;
    }
}
