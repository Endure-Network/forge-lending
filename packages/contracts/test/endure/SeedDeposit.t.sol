// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@test/helper/EndureDeployHelper.sol";
import {EndureRoles} from "@protocol/endure/EndureRoles.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {InterestRateModel} from "@protocol/irm/InterestRateModel.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";
import {EnduRateModelParams} from "@protocol/endure/EnduRateModelParams.sol";
import {MToken} from "@protocol/MToken.sol";

contract SeedDepositTest is Test, EndureDeployHelper {
    EndureDeployHelper.Addresses addrs;
    Comptroller comptroller;
    MErc20Delegator mWTAO;
    MErc20Delegator mMockAlpha30;
    MErc20Delegator mMockAlpha64;
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
        mWTAO = MErc20Delegator(payable(addrs.mWTAO));
        mMockAlpha30 = MErc20Delegator(payable(addrs.mMockAlpha30));
        mMockAlpha64 = MErc20Delegator(payable(addrs.mMockAlpha64));
        mockAlpha30 = MockAlpha30(addrs.mockAlpha30);
        wtao = WTAO(addrs.wtao);
    }

    function test_EveryMarketHasPositiveTotalSupply() public view {
        assertGt(mWTAO.totalSupply(), 0, "mWTAO totalSupply == 0");
        assertGt(mMockAlpha30.totalSupply(), 0, "mMockAlpha30 totalSupply == 0");
        assertGt(mMockAlpha64.totalSupply(), 0, "mMockAlpha64 totalSupply == 0");
    }

    function test_DeadAddressHoldsSeedMTokens() public view {
        address dead = address(0xdEaD);
        assertGt(mWTAO.balanceOf(dead), 0, "mWTAO dEaD balance == 0");
        assertGt(mMockAlpha30.balanceOf(dead), 0, "mMockAlpha30 dEaD balance == 0");
        assertGt(mMockAlpha64.balanceOf(dead), 0, "mMockAlpha64 dEaD balance == 0");
    }

    function test_SeedAmountMatchesConstant() public view {
        uint256 rate = mMockAlpha30.exchangeRateStored();
        uint256 deadBal = mMockAlpha30.balanceOf(address(0xdEaD));
        uint256 underlyingEquiv = (deadBal * rate) / 1e18;

        assertApproxEqAbs(
            underlyingEquiv,
            EnduRateModelParams.SEED_AMOUNT,
            1,
            "seed amount mismatch"
        );
    }

    function test_Negative_AlphaBorrowBlockedByCap() public {
        mockAlpha30.mint(alice, 100e18);
        vm.startPrank(alice);
        mockAlpha30.approve(address(mMockAlpha30), 100e18);
        uint256 mintErr = mMockAlpha30.mint(100e18);
        assertEq(mintErr, 0, "collateral mint failed");

        address[] memory markets = new address[](1);
        markets[0] = address(mMockAlpha30);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        wtao.mint(supplier, 1000e18);
        vm.startPrank(supplier);
        wtao.approve(address(mWTAO), 1000e18);
        uint256 supplyErr = mWTAO.mint(1000e18);
        assertEq(supplyErr, 0, "liquidity mint failed");
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(bytes("market borrow cap reached"));
        mMockAlpha30.borrow(1e18);
        vm.stopPrank();
    }

    function test_Negative_SetCFBeforeOracleReverts() public {
        MockAlpha30 newUnderlying = new MockAlpha30();
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

        uint256 supportErr = comptroller._supportMarket(MToken(address(newMToken)));
        assertEq(supportErr, 0, "support market failed");
        assertEq(
            comptroller.oracle().getUnderlyingPrice(MToken(address(newMToken))),
            0,
            "expected zero price for unknown market"
        );

        uint256 err = comptroller._setCollateralFactor(
            MToken(address(newMToken)),
            0.25e18
        );
        assertGt(err, 0, "expected error for zero-price CF");
    }
}
