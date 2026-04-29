// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@protocol/endure/EndureDeployHelper.sol";
import {VBep20Immutable} from "@protocol/Tokens/VTokens/VBep20Immutable.sol";
import {VToken} from "@protocol/Tokens/VTokens/VToken.sol";
import {MarketFacet} from "@protocol/Comptroller/Diamond/facets/MarketFacet.sol";
import {PolicyFacet} from "@protocol/Comptroller/Diamond/facets/PolicyFacet.sol";
import {MockResilientOracle} from "@protocol/endure/MockResilientOracle.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";

/// @title LiquidationThresholdTest
/// @notice Proves LT is used for liquidation eligibility, separately from CF.
///         CF = 0.25, LT = 0.35 for alpha markets.
contract LiquidationThresholdTest is Test {
    EndureDeployHelper helper;
    EndureDeployHelper.Addresses addrs;

    VBep20Immutable vAlpha30;
    VBep20Immutable vWTAO;
    MockResilientOracle oracle;
    MockAlpha30 mockAlpha30;
    WTAO wtao;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address supplier = makeAddr("supplier");

    function setUp() public {
        helper = new EndureDeployHelper();
        addrs = helper.deployAll();
        vAlpha30 = VBep20Immutable(payable(addrs.vAlpha30));
        vWTAO = VBep20Immutable(payable(addrs.vWTAO));
        oracle = MockResilientOracle(addrs.resilientOracle);
        mockAlpha30 = MockAlpha30(addrs.mockAlpha30);
        wtao = WTAO(addrs.wtao);

        vm.prank(address(helper));
        oracle.setAdmin(address(this));

        // Alice: 100e18 alpha collateral, enters market
        mockAlpha30.mint(alice, 100e18);
        vm.startPrank(alice);
        mockAlpha30.approve(address(vAlpha30), 100e18);
        assertEq(vAlpha30.mint(100e18), 0, "alice supply");
        address[] memory markets = new address[](1);
        markets[0] = address(vAlpha30);
        MarketFacet(addrs.unitroller).enterMarkets(markets);
        vm.stopPrank();

        // Supplier: WTAO liquidity
        wtao.mint(supplier, 1_000e18);
        vm.startPrank(supplier);
        wtao.approve(address(vWTAO), 1_000e18);
        assertEq(vWTAO.mint(1_000e18), 0, "supplier mint");
        vm.stopPrank();

        // Alice borrows 20e18 WTAO
        vm.prank(alice);
        assertEq(vWTAO.borrow(20e18), 0, "alice borrow");
    }

    /// @notice At CF utilization boundary (price 0.8), Alice can't borrow more,
    ///         but she is NOT liquidatable because LT (0.35) gives more headroom.
    ///         CF boundary: 20 / (100 * 0.25) = 0.8
    ///         LT check at 0.8: 100 * 0.8 * 0.35 = 28 > 20 → safe.
    function test_InCFLTGap_NotLiquidatable() public {
        oracle.setUnderlyingPrice(addrs.vAlpha30, 0.8e18);

        (, , uint256 shortfall) = PolicyFacet(addrs.unitroller).getAccountLiquidity(alice);
        assertEq(shortfall, 0, "should NOT be in shortfall at CF boundary");

        // Liquidation attempt should fail
        wtao.mint(bob, 5e18);
        vm.startPrank(bob);
        wtao.approve(address(vWTAO), 5e18);
        uint256 err = vWTAO.liquidateBorrow(alice, 5e18, VToken(address(vAlpha30)));
        assertGt(err, 0, "liquidation should fail in CF/LT gap");
        vm.stopPrank();
    }

    /// @notice At LT utilization boundary (price drops below ~0.5714), Alice IS liquidatable.
    ///         LT boundary: 20 / (100 * 0.35) = 0.5714
    ///         At 0.56: 100 * 0.56 * 0.35 = 19.6 < 20 → shortfall → liquidatable.
    function test_PastLTBoundary_Liquidatable() public {
        oracle.setUnderlyingPrice(addrs.vAlpha30, 0.56e18);

        (, , uint256 shortfall) = PolicyFacet(addrs.unitroller).getAccountLiquidity(alice);
        assertGt(shortfall, 0, "should be in shortfall past LT boundary");

        // Liquidation must succeed
        wtao.mint(bob, 5e18);
        vm.startPrank(bob);
        wtao.approve(address(vWTAO), 5e18);
        assertEq(
            vWTAO.liquidateBorrow(alice, 5e18, VToken(address(vAlpha30))),
            0,
            "liquidation should succeed past LT boundary"
        );
        vm.stopPrank();

        assertGt(vAlpha30.balanceOf(bob), 0, "bob should receive seized vAlpha30");
    }
}
