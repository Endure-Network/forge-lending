// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@test/helper/EndureDeployHelper.sol";
import {EndureRoles} from "@protocol/endure/EndureRoles.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";

contract AliceLifecycleTest is Test, EndureDeployHelper {
    EndureDeployHelper.Addresses addrs;
    Comptroller comptroller;
    MErc20Delegator mMockAlpha30;
    MErc20Delegator mWTAO;
    MockAlpha30 mockAlpha30;
    WTAO wtao;

    address alice = makeAddr("alice");
    address supplier = makeAddr("supplier");

    function setUp() public {
        vm.warp(block.timestamp + 1 days);
        EndureRoles.RoleSet memory roles = EndureRoles.RoleSet({
            admin: address(this),
            pauseGuardian: address(this),
            borrowCapGuardian: address(this),
            supplyCapGuardian: address(this)
        });
        addrs = _deployAs(roles);
        comptroller = Comptroller(addrs.comptrollerProxy);
        mMockAlpha30 = MErc20Delegator(payable(addrs.mMockAlpha30));
        mWTAO = MErc20Delegator(payable(addrs.mWTAO));
        mockAlpha30 = MockAlpha30(addrs.mockAlpha30);
        wtao = WTAO(addrs.wtao);
    }

    function test_Integration_AliceFullLifecycle() public {
        // 1. Mint Alice 100e18 MockAlpha30
        mockAlpha30.mint(alice, 100e18);

        // 2. Alice approves and supplies MockAlpha30
        vm.startPrank(alice);
        mockAlpha30.approve(address(mMockAlpha30), 100e18);
        uint256 mintErr = mMockAlpha30.mint(100e18);
        assertEq(mintErr, 0, "mint failed");
        assertGt(mMockAlpha30.balanceOf(alice), 0, "no mTokens");

        // 3. Alice enters market
        address[] memory markets = new address[](1);
        markets[0] = address(mMockAlpha30);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        // 4. Supplier provides WTAO liquidity
        wtao.mint(supplier, 1000e18);
        vm.startPrank(supplier);
        wtao.approve(address(mWTAO), 1000e18);
        uint256 supplyErr = mWTAO.mint(1000e18);
        assertEq(supplyErr, 0, "supplier mint failed");
        vm.stopPrank();

        // 5. Alice borrows 10e18 WTAO
        vm.prank(alice);
        uint256 borrowErr = mWTAO.borrow(10e18);
        assertEq(borrowErr, 0, "borrow failed");
        assertEq(wtao.balanceOf(alice), 10e18, "wrong borrow amount");

        // 6. Advance 30 days
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 216000);

        // 7. Check interest accrued
        uint256 debt = mWTAO.borrowBalanceCurrent(alice);
        assertGt(debt, 10e18, "no interest accrued");

        // 8. Alice repays full debt
        wtao.mint(alice, debt);
        vm.startPrank(alice);
        wtao.approve(address(mWTAO), debt);
        uint256 repayErr = mWTAO.repayBorrow(debt);
        assertEq(repayErr, 0, "repay failed");
        assertEq(mWTAO.borrowBalanceCurrent(alice), 0, "debt not cleared");

        // 9. Alice redeems collateral
        uint256 mTokenBal = mMockAlpha30.balanceOf(alice);
        uint256 redeemErr = mMockAlpha30.redeem(mTokenBal);
        assertEq(redeemErr, 0, "redeem failed");
        assertGt(mockAlpha30.balanceOf(alice), 95e18, "lost too much collateral");

        // 10. Alice exits market
        uint256 exitErr = comptroller.exitMarket(address(mMockAlpha30));
        assertEq(exitErr, 0, "exit market failed");
        vm.stopPrank();
    }
}
