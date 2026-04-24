// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@test/helper/EndureDeployHelper.sol";
import {EndureRoles} from "@protocol/endure/EndureRoles.sol";
import {EnduRateModelParams} from "@protocol/endure/EnduRateModelParams.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {InterestRateModel} from "@protocol/irm/InterestRateModel.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {MockPriceOracle} from "@protocol/endure/MockPriceOracle.sol";
import {MToken} from "@protocol/MToken.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";

contract LiquidationTest is Test, EndureDeployHelper {
    EndureDeployHelper.Addresses addrs;
    Comptroller comptroller;
    MErc20Delegator mMockAlpha30;
    MErc20Delegator mWTAO;
    MockAlpha30 mockAlpha30;
    MockPriceOracle mockOracle;
    WTAO wtao;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
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
        mockOracle = MockPriceOracle(addrs.mockPriceOracle);
        wtao = WTAO(addrs.wtao);

        // Setup: Alice supplies alpha30, supplier provides WTAO
        mockAlpha30.mint(alice, 100e18);
        vm.startPrank(alice);
        mockAlpha30.approve(address(mMockAlpha30), 100e18);
        mMockAlpha30.mint(100e18);
        address[] memory markets = new address[](1);
        markets[0] = address(mMockAlpha30);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        wtao.mint(supplier, 1000e18);
        vm.startPrank(supplier);
        wtao.approve(address(mWTAO), 1000e18);
        mWTAO.mint(1000e18);
        vm.stopPrank();
    }

    function test_Integration_LiquidationOnPriceDrop() public {
        // Alice borrows 10e18 WTAO
        vm.prank(alice);
        uint256 borrowErr = mWTAO.borrow(10e18);
        assertEq(borrowErr, 0, "borrow failed");

        // Drop alpha30 price: 1 TAO -> 0.3 TAO (triggers shortfall)
        mockOracle.setUnderlyingPrice(MToken(address(mMockAlpha30)), 3e17);

        // Verify shortfall
        (, , uint256 shortfall) = comptroller.getAccountLiquidity(alice);
        assertGt(shortfall, 0, "no shortfall after price drop");

        // Bob liquidates
        wtao.mint(bob, 5e18);
        vm.startPrank(bob);
        wtao.approve(address(mWTAO), 5e18);
        uint256 liqErr = mWTAO.liquidateBorrow(alice, 5e18, mMockAlpha30);
        assertEq(liqErr, 0, "liquidation failed");
        vm.stopPrank();

        assertGt(mMockAlpha30.balanceOf(bob), 0, "bob got no collateral");
        assertLt(mWTAO.borrowBalanceCurrent(alice), 10e18, "debt not reduced");
    }

    function test_Negative_LiquidationHealthyReverts() public {
        // Alice borrows but price hasn't dropped — healthy
        vm.prank(alice);
        mWTAO.borrow(5e18);

        wtao.mint(bob, 1e18);
        vm.startPrank(bob);
        wtao.approve(address(mWTAO), 1e18);
        // Liquidation on healthy account should fail (non-zero error code or revert)
        try mWTAO.liquidateBorrow(alice, 1e18, mMockAlpha30) returns (uint256 err) {
            assertGt(err, 0, "expected non-zero error for healthy liquidation");
        } catch {
            // revert is also acceptable
        }
        vm.stopPrank();
    }

    function test_Negative_ZeroPriceOracleReverts() public {
        // Deploy a fresh underlying with no oracle price
        MockAlpha30 newUnderlying = new MockAlpha30();

        // Deploy a new MErc20Delegator for this underlying
        MErc20Delegator newMToken = new MErc20Delegator(
            address(newUnderlying),
            comptroller,
            InterestRateModel(addrs.jumpRateModel_mMockAlpha30),
            EnduRateModelParams.INITIAL_EXCHANGE_RATE_MANTISSA,
            "Test No Price",
            "mNOPRICE",
            18,
            payable(address(this)),
            addrs.mErc20Delegate,
            ""
        );

        // Support the market (does NOT require price)
        uint256 supportErr = comptroller._supportMarket(MToken(address(newMToken)));
        assertEq(supportErr, 0, "support market failed");

        // Do NOT set oracle price — price remains 0

        // _setCollateralFactor should fail with non-zero error (price error)
        uint256 cfErr = comptroller._setCollateralFactor(
            MToken(address(newMToken)),
            0.25e18
        );
        assertGt(cfErr, 0, "expected non-zero error for zero-price CF setting");

        // Verify oracle indeed returns 0
        assertEq(mockOracle.getUnderlyingPrice(MToken(address(newMToken))), 0, "expected zero price");
    }
}
