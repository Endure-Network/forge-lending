// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IProtocolShareReserve} from "../external/IProtocolShareReserve.sol";

contract LocalProtocolShareReserve is IProtocolShareReserve {
    mapping(address => mapping(address => uint256)) public assetReserves;
    mapping(address => uint256) public totalAssetReserve;

    event AssetsReservesUpdated(
        address indexed comptroller,
        address indexed asset,
        uint256 amount,
        IncomeType indexed incomeType
    );

    function updateAssetsState(address comptroller, address asset, IncomeType incomeType) external {
        require(comptroller != address(0), "comptroller zero");
        require(asset != address(0), "asset zero");

        uint256 currentBalance = IERC20(asset).balanceOf(address(this));
        uint256 previousBalance = totalAssetReserve[asset];
        if (currentBalance <= previousBalance) {
            return;
        }

        uint256 delta = currentBalance - previousBalance;
        assetReserves[comptroller][asset] += delta;
        totalAssetReserve[asset] = currentBalance;
        emit AssetsReservesUpdated(comptroller, asset, delta, incomeType);
    }
}
