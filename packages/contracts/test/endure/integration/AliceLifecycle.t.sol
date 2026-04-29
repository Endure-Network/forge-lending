// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelperVenus} from "@test/helper/EndureDeployHelperVenus.sol";
import {VBep20Immutable} from "@protocol/Tokens/VTokens/VBep20Immutable.sol";
import {MarketFacet} from "@protocol/Comptroller/Diamond/facets/MarketFacet.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";

contract AliceLifecycleTest is Test {
    EndureDeployHelperVenus helper;
    EndureDeployHelperVenus.VenusAddresses addrs;

    VBep20Immutable vAlpha30;
    VBep20Immutable vWTAO;
    MockAlpha30 mockAlpha30;
    WTAO wtao;

    address alice = makeAddr("alice");
    address supplier = makeAddr("supplier");

    function setUp() public {
        helper = new EndureDeployHelperVenus();
        addrs = helper.deployAll();
        vAlpha30 = VBep20Immutable(payable(addrs.vAlpha30));
        vWTAO = VBep20Immutable(payable(addrs.vWTAO));
        mockAlpha30 = MockAlpha30(addrs.mockAlpha30);
        wtao = WTAO(addrs.wtao);

        // Supplier provides WTAO liquidity for borrowing
        wtao.mint(supplier, 1_000e18);
        vm.startPrank(supplier);
        wtao.approve(address(vWTAO), 1_000e18);
        assertEq(vWTAO.mint(1_000e18), 0, "supplier mint failed");
        vm.stopPrank();
    }

    function test_Integration_AliceFullLifecycle() public {
        uint256 supplyAmount = 100e18;
        uint256 borrowAmount = 10e18;

        // 1. Mint Alice 100e18 MockAlpha30
        mockAlpha30.mint(alice, supplyAmount);

        vm.startPrank(alice);

        // 2. Alice approves and supplies MockAlpha30
        mockAlpha30.approve(address(vAlpha30), supplyAmount);
        assertEq(vAlpha30.mint(supplyAmount), 0, "mint vAlpha30");
        assertGt(vAlpha30.balanceOf(alice), 0, "no vTokens");

        // 3. Alice enters market
        address[] memory markets = new address[](1);
        markets[0] = address(vAlpha30);
        uint256[] memory results = MarketFacet(addrs.unitroller).enterMarkets(markets);
        assertEq(results[0], 0, "enterMarkets vAlpha30");

        // 4. Alice borrows WTAO
        assertEq(vWTAO.borrow(borrowAmount), 0, "borrow vWTAO");
        assertEq(wtao.balanceOf(alice), borrowAmount, "wrong borrow amount");

        // 5. Alice repays full debt
        wtao.approve(address(vWTAO), type(uint256).max);
        assertEq(vWTAO.repayBorrow(borrowAmount), 0, "repay vWTAO");
        assertEq(vWTAO.borrowBalanceStored(alice), 0, "debt not cleared");

        // 6. Alice redeems collateral
        uint256 vAlphaBalance = vAlpha30.balanceOf(alice);
        assertGt(vAlphaBalance, 0, "alice has no vAlpha30");
        assertEq(vAlpha30.redeem(vAlphaBalance), 0, "redeem vAlpha30");
        assertEq(vAlpha30.balanceOf(alice), 0, "vAlpha30 balance not zero after redeem");
        assertGt(mockAlpha30.balanceOf(alice), 0, "alice received no underlying alpha after redeem");

        vm.stopPrank();
    }
}
