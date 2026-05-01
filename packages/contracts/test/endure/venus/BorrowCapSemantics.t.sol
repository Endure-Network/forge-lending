// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@protocol/endure/EndureDeployHelper.sol";
import {VBep20Immutable} from "@protocol/Tokens/VTokens/VBep20Immutable.sol";
import {VToken} from "@protocol/Tokens/VTokens/VToken.sol";
import {MarketFacet} from "@protocol/Comptroller/Diamond/facets/MarketFacet.sol";
import {SetterFacet} from "@protocol/Comptroller/Diamond/facets/SetterFacet.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";

/// @title BorrowCapSemanticsTest
/// @notice Proves Venus borrow cap semantics: cap=type(uint256).max -> unlimited,
///         cap=0 -> DISABLED (no borrowing allowed).
contract BorrowCapSemanticsTest is Test {
    EndureDeployHelper helper;
    EndureDeployHelper.Addresses addrs;

    VBep20Immutable vAlpha30;
    VBep20Immutable vWTAO;
    MockAlpha30 mockAlpha30;
    WTAO wtao;

    address alice = makeAddr("alice");
    address supplier = makeAddr("supplier");

    function setUp() public {
        helper = new EndureDeployHelper();
        addrs = helper.deployAll();
        vAlpha30 = VBep20Immutable(payable(addrs.vAlpha30));
        vWTAO = VBep20Immutable(payable(addrs.vWTAO));
        mockAlpha30 = MockAlpha30(addrs.mockAlpha30);
        wtao = WTAO(addrs.wtao);

        // Alice: supply alpha collateral, enter market
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
    }

    /// @notice vWTAO borrowCaps == type(uint256).max -> borrow succeeds (unlimited).
    function test_UnlimitedBorrowCap_BorrowSucceeds() public {
        // Verify cap is unlimited
        (bool ok, bytes memory data) =
            addrs.unitroller.staticcall(abi.encodeWithSignature("borrowCaps(address)", addrs.vWTAO));
        require(ok, "borrowCaps call failed");
        uint256 cap = abi.decode(data, (uint256));
        assertEq(cap, type(uint256).max, "vWTAO borrow cap should be unlimited");

        // Borrow succeeds
        vm.prank(alice);
        assertEq(vWTAO.borrow(5e18), 0, "borrow should succeed with unlimited cap");
    }

    /// @notice vAlpha30 borrowCaps == 0 -> Venus reverts: "market borrow cap is 0".
    ///         We enable isBorrowAllowed to isolate the cap check, proving
    ///         cap=0 alone blocks borrowing (Venus semantics differ from Compound).
    function test_ZeroBorrowCap_BorrowDisabled() public {
        // Verify cap is 0
        (bool ok, bytes memory data) =
            addrs.unitroller.staticcall(abi.encodeWithSignature("borrowCaps(address)", addrs.vAlpha30));
        require(ok, "borrowCaps call failed");
        uint256 cap = abi.decode(data, (uint256));
        assertEq(cap, 0, "vAlpha30 borrow cap should be 0 (disabled)");

        // Enable isBorrowAllowed to isolate the cap=0 behavior
        SetterFacet(addrs.unitroller).setIsBorrowAllowed(0, addrs.vAlpha30, true);

        // Supply alpha liquidity for borrow attempt
        mockAlpha30.mint(supplier, 100e18);
        vm.startPrank(supplier);
        mockAlpha30.approve(address(vAlpha30), 100e18);
        assertEq(vAlpha30.mint(100e18), 0, "supplier alpha supply");
        vm.stopPrank();

        // Borrow reverts because cap=0 disables borrowing in Venus
        vm.prank(alice);
        vm.expectRevert(bytes("market borrow cap is 0"));
        vAlpha30.borrow(1e18);
    }
}
