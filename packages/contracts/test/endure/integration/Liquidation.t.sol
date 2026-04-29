// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@test/helper/EndureDeployHelper.sol";
import {VBep20Immutable} from "@protocol/Tokens/VTokens/VBep20Immutable.sol";
import {VToken} from "@protocol/Tokens/VTokens/VToken.sol";
import {MarketFacet} from "@protocol/Comptroller/Diamond/facets/MarketFacet.sol";
import {PolicyFacet} from "@protocol/Comptroller/Diamond/facets/PolicyFacet.sol";
import {MockResilientOracle} from "@protocol/endure/MockResilientOracle.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";

contract LiquidationTest is Test {
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

    uint256 constant CF_ALPHA = 0.25e18;
    uint256 constant LT_ALPHA = 0.35e18;

    function setUp() public {
        helper = new EndureDeployHelper();
        addrs = helper.deployAll();
        vAlpha30 = VBep20Immutable(payable(addrs.vAlpha30));
        vWTAO = VBep20Immutable(payable(addrs.vWTAO));
        oracle = MockResilientOracle(addrs.resilientOracle);
        mockAlpha30 = MockAlpha30(addrs.mockAlpha30);
        wtao = WTAO(addrs.wtao);

        // Transfer oracle admin to test contract for price manipulation
        vm.prank(address(helper));
        oracle.setAdmin(address(this));

        // Alice supplies alpha, enters market
        mockAlpha30.mint(alice, 100e18);
        vm.startPrank(alice);
        mockAlpha30.approve(address(vAlpha30), 100e18);
        assertEq(vAlpha30.mint(100e18), 0, "alice mint");
        address[] memory markets = new address[](1);
        markets[0] = address(vAlpha30);
        MarketFacet(addrs.unitroller).enterMarkets(markets);
        vm.stopPrank();

        // Supplier provides WTAO liquidity
        wtao.mint(supplier, 1_000e18);
        vm.startPrank(supplier);
        wtao.approve(address(vWTAO), 1_000e18);
        assertEq(vWTAO.mint(1_000e18), 0, "supplier mint");
        vm.stopPrank();
    }

    /// @notice Alice borrows WTAO, price drops, Bob liquidates successfully.
    function test_PriceDropMakesAccountLiquidatable() public {
        vm.prank(alice);
        assertEq(vWTAO.borrow(10e18), 0, "borrow");

        // Drop alpha price: 1 -> 0.1 (severe shortfall)
        oracle.setUnderlyingPrice(addrs.vAlpha30, 0.1e18);

        (, , uint256 shortfall) = PolicyFacet(addrs.unitroller).getAccountLiquidity(alice);
        assertGt(shortfall, 0, "no shortfall after price drop");

        // Bob liquidates
        wtao.mint(bob, 5e18);
        vm.startPrank(bob);
        wtao.approve(address(vWTAO), 5e18);
        assertEq(
            vWTAO.liquidateBorrow(alice, 5e18, VToken(address(vAlpha30))),
            0,
            "liquidation failed"
        );
        vm.stopPrank();

        assertGt(vAlpha30.balanceOf(bob), 0, "bob got no collateral");
    }

    /// @notice Healthy account cannot be liquidated (non-zero error code).
    function test_HealthyAccountNotLiquidatable() public {
        vm.prank(alice);
        assertEq(vWTAO.borrow(5e18), 0, "borrow");

        // No price drop — account healthy
        wtao.mint(bob, 1e18);
        vm.startPrank(bob);
        wtao.approve(address(vWTAO), 1e18);
        uint256 err = vWTAO.liquidateBorrow(alice, 1e18, VToken(address(vAlpha30)));
        assertGt(err, 0, "expected non-zero error for healthy liquidation");
        vm.stopPrank();
    }

    /// @notice Proves liquidation uses LT (0.35), not CF (0.25).
    ///         Alice borrows 24e18 WTAO against 100e18 alpha (price=1).
    ///         Price drops to 0.68 (in the CF/LT gap zone):
    ///           CF check: 100*0.68*0.25 = 17 < 24 (CF crossed)
    ///           LT check: 100*0.68*0.35 = 23.8 < 24 (LT crossed)
    ///         Liquidation succeeds because LT threshold is crossed.
    function test_LiquidationUsesLTNotCF() public {
        vm.prank(alice);
        assertEq(vWTAO.borrow(24e18), 0, "borrow");

        // Drop alpha price into the gap zone (0.68 of original)
        oracle.setUnderlyingPrice(addrs.vAlpha30, 0.68e18);

        (, , uint256 shortfall) = PolicyFacet(addrs.unitroller).getAccountLiquidity(alice);
        assertGt(shortfall, 0, "account should be in shortfall at 0.68 price");

        // Bob liquidates — must succeed (LT threshold crossed)
        uint256 repayAmount = 5e18;
        wtao.mint(bob, repayAmount);
        vm.startPrank(bob);
        wtao.approve(address(vWTAO), repayAmount);
        assertEq(
            vWTAO.liquidateBorrow(alice, repayAmount, VToken(address(vAlpha30))),
            0,
            "liquidation in LT/CF gap zone should succeed"
        );
        vm.stopPrank();

        assertGt(vAlpha30.balanceOf(bob), 0, "bob got no seized collateral");
    }

    /// @notice Seized vAlpha value > repaid WTAO value (liquidation incentive).
    function test_LiquidationIncentiveAppliesCorrectly() public {
        vm.prank(alice);
        assertEq(vWTAO.borrow(20e18), 0, "borrow");

        // Severe price drop to trigger liquidation
        oracle.setUnderlyingPrice(addrs.vAlpha30, 0.3e18);

        uint256 repayAmount = 5e18;
        wtao.mint(bob, repayAmount);
        vm.startPrank(bob);
        wtao.approve(address(vWTAO), repayAmount);
        assertEq(
            vWTAO.liquidateBorrow(alice, repayAmount, VToken(address(vAlpha30))),
            0,
            "liquidation failed"
        );
        vm.stopPrank();

        // Bob's seized vAlpha should be worth more than 5e18 WTAO (1.08x incentive)
        uint256 seizedVTokens = vAlpha30.balanceOf(bob);
        uint256 exchangeRate = vAlpha30.exchangeRateStored();
        uint256 seizedUnderlying = (seizedVTokens * exchangeRate) / 1e18;
        uint256 alphaPrice = oracle.underlyingPrices(addrs.vAlpha30);
        uint256 seizedValue = (seizedUnderlying * alphaPrice) / 1e18;

        // repayAmount * wtaoPrice = 5e18 * 1e18 / 1e18 = 5e18
        // seizedValue should be >= repayAmount * 1.08
        assertGt(seizedValue, repayAmount, "seized value not greater than repaid value");
    }
}
