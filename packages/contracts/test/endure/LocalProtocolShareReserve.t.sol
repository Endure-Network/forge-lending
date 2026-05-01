// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {LocalProtocolShareReserve} from "@protocol/endure/LocalProtocolShareReserve.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {IProtocolShareReserve} from "@protocol/external/IProtocolShareReserve.sol";

contract LocalProtocolShareReserveTest is Test {
    LocalProtocolShareReserve reserve;
    MockAlpha30 token;

    address comptroller = makeAddr("comptroller");

    function setUp() public {
        reserve = new LocalProtocolShareReserve();
        token = new MockAlpha30();
    }

    function test_UpdateAssetsState_RevertsIfComptrollerZero() public {
        vm.expectRevert(bytes("comptroller zero"));
        reserve.updateAssetsState(address(0), address(token), IProtocolShareReserve.IncomeType.SPREAD);
    }

    function test_UpdateAssetsState_RevertsIfAssetZero() public {
        vm.expectRevert(bytes("asset zero"));
        reserve.updateAssetsState(comptroller, address(0), IProtocolShareReserve.IncomeType.SPREAD);
    }

    function test_UpdateAssetsState_NoOpsWhenBalanceDoesNotIncrease() public {
        vm.recordLogs();
        reserve.updateAssetsState(comptroller, address(token), IProtocolShareReserve.IncomeType.SPREAD);

        assertEq(vm.getRecordedLogs().length, 0, "no event");
        assertEq(reserve.totalAssetReserve(address(token)), 0, "total reserve");
        assertEq(reserve.assetReserves(comptroller, address(token)), 0, "comptroller reserve");
    }

    function test_UpdateAssetsState_AccumulatesDeltaAndEmitsEvent() public {
        token.mint(address(reserve), 5e18);

        vm.expectEmit(true, true, true, true);
        emit LocalProtocolShareReserve.AssetsReservesUpdated(
            comptroller,
            address(token),
            5e18,
            IProtocolShareReserve.IncomeType.LIQUIDATION
        );
        reserve.updateAssetsState(comptroller, address(token), IProtocolShareReserve.IncomeType.LIQUIDATION);

        assertEq(reserve.totalAssetReserve(address(token)), 5e18, "total reserve");
        assertEq(reserve.assetReserves(comptroller, address(token)), 5e18, "comptroller reserve");
    }

    function test_UpdateAssetsState_AccumulatesOnlyNewBalanceAcrossCalls() public {
        token.mint(address(reserve), 3e18);
        reserve.updateAssetsState(comptroller, address(token), IProtocolShareReserve.IncomeType.SPREAD);

        token.mint(address(reserve), 7e18);
        reserve.updateAssetsState(comptroller, address(token), IProtocolShareReserve.IncomeType.LIQUIDATION);

        assertEq(reserve.totalAssetReserve(address(token)), 10e18, "total reserve");
        assertEq(reserve.assetReserves(comptroller, address(token)), 10e18, "comptroller reserve");
    }

    function test_UpdateAssetsState_UsesGlobalAssetBaselineAcrossComptrollers() public {
        address secondComptroller = makeAddr("second comptroller");
        token.mint(address(reserve), 10e18);

        reserve.updateAssetsState(comptroller, address(token), IProtocolShareReserve.IncomeType.SPREAD);
        reserve.updateAssetsState(secondComptroller, address(token), IProtocolShareReserve.IncomeType.SPREAD);

        assertEq(reserve.assetReserves(comptroller, address(token)), 10e18, "first reserve");
        assertEq(reserve.assetReserves(secondComptroller, address(token)), 0, "second reserve");
        assertEq(reserve.totalAssetReserve(address(token)), 10e18, "global baseline");
    }
}
