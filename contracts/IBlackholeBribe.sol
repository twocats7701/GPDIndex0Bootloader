// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBlackholeBribe {
    function depositBribe(address token, uint256 amount) external;
    function claimBribe(address token) external returns (uint256);
    function notifyBribe(address token, uint256 amount) external;
}

