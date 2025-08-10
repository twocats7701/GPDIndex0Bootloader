// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IAssetPolicy.sol";
import "./interfaces/IOtcAdapterPASS.sol";

contract FateAccumulatorVault is ERC4626 {
    using SafeERC20 for IERC20;

    IAssetPolicy public assetPolicy;
    IOtcAdapterPASS public otc;

    struct PnL { uint256 realized; uint256 unrealized; }
    mapping(uint256 => PnL) private floorPnl;

    constructor(
        IERC20 asset_,
        address policy_,
        address otc_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC4626(asset_) {
        assetPolicy = IAssetPolicy(policy_);
        otc = IOtcAdapterPASS(otc_);
    }

    function realized(uint256 floor) external view returns (uint256) {
        return floorPnl[floor].realized;
    }

    function unrealized(uint256 floor) external view returns (uint256) {
        return floorPnl[floor].unrealized;
    }

    function _preTrade() internal view {
        require(assetPolicy.isPriceWithinBand(), "KillSwitch");
        require(assetPolicy.isOracleValid(), "KillSwitch");
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _preTrade();
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);
        uint256 floor = assetPolicy.currentFloor();
        floorPnl[floor].unrealized += assets;
        _mint(receiver, shares);
    }

    function _withdraw(address /*caller*/, address receiver, address owner, uint256 assets, uint256 shares) internal override {
        _preTrade();
        _burn(owner, shares);
        uint256 floor = assetPolicy.currentFloor();
        floorPnl[floor].unrealized -= assets;
        floorPnl[floor].realized += assets;

        if (assetPolicy.areDexSellsGated()) {
            IERC20(asset()).safeApprove(address(otc), assets);
            otc.sell(address(asset()), assets, receiver);
        } else {
            IERC20(asset()).safeTransfer(receiver, assets);
        }
    }
}
