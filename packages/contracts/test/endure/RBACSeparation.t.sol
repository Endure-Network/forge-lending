// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@test/helper/EndureDeployHelper.sol";
import {EndureRoles} from "@protocol/endure/EndureRoles.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MToken} from "@protocol/MToken.sol";

contract RBACSeparationTest is Test, EndureDeployHelper {
    EndureDeployHelper.Addresses addrs;
    Comptroller comptroller;
    MErc20Delegator mMockAlpha30;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address dave = makeAddr("dave");
    address eve = makeAddr("eve");

    function setUp() public {
        EndureRoles.RoleSet memory roles = EndureRoles.RoleSet({
            admin: alice,
            pauseGuardian: bob,
            borrowCapGuardian: carol,
            supplyCapGuardian: dave
        });
        addrs = _deployAs(roles);
        comptroller = Comptroller(addrs.comptrollerProxy);
        mMockAlpha30 = MErc20Delegator(payable(addrs.mMockAlpha30));
    }

    function test_AdminCanDoEverything() public {
        vm.startPrank(alice);
        MToken[] memory markets = new MToken[](1);
        markets[0] = MToken(addrs.mMockAlpha30);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 5000e18;
        comptroller._setMarketBorrowCaps(markets, caps);
        comptroller._setMarketSupplyCaps(markets, caps);
        comptroller._setMintPaused(MToken(address(mMockAlpha30)), true);
        comptroller._setMintPaused(MToken(address(mMockAlpha30)), false);
        vm.stopPrank();
    }

    function test_PauseGuardianCanPauseCannotUnpause() public {
        vm.prank(bob);
        comptroller._setMintPaused(MToken(address(mMockAlpha30)), true);
        vm.prank(bob);
        vm.expectRevert();
        comptroller._setMintPaused(MToken(address(mMockAlpha30)), false);
        vm.prank(alice);
        comptroller._setMintPaused(MToken(address(mMockAlpha30)), false);
    }

    function test_PauseGuardianCannotChangeCF() public {
        vm.prank(bob);
        uint256 err = comptroller._setCollateralFactor(
            MToken(address(mMockAlpha30)),
            0.1e18
        );
        assertGt(err, 0, "expected non-zero error code");
    }

    function test_BorrowCapGuardianCanSetBorrowCapsOnly() public {
        MToken[] memory markets = new MToken[](1);
        markets[0] = MToken(addrs.mMockAlpha30);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 5;
        vm.prank(carol);
        comptroller._setMarketBorrowCaps(markets, caps);
        caps[0] = 100e18;
        vm.prank(carol);
        vm.expectRevert();
        comptroller._setMarketSupplyCaps(markets, caps);
    }

    function test_SupplyCapGuardianCanSetSupplyCapsOnly() public {
        MToken[] memory markets = new MToken[](1);
        markets[0] = MToken(addrs.mMockAlpha30);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 20000e18;
        vm.prank(dave);
        comptroller._setMarketSupplyCaps(markets, caps);
        caps[0] = 5;
        vm.prank(dave);
        vm.expectRevert();
        comptroller._setMarketBorrowCaps(markets, caps);
    }

    function test_GuardiansCannotAppointSuccessors() public {
        vm.prank(bob);
        uint256 err = comptroller._setPauseGuardian(eve);
        assertGt(err, 0, "pause guardian should not appoint successor");
        vm.prank(carol);
        vm.expectRevert();
        comptroller._setBorrowCapGuardian(eve);
        vm.prank(dave);
        vm.expectRevert();
        comptroller._setSupplyCapGuardian(eve);
    }

    function test_MTokenAdminIsIndependent() public {
        address frank = makeAddr("frank");
        vm.prank(alice);
        mMockAlpha30._setPendingAdmin(payable(frank));
        vm.prank(frank);
        mMockAlpha30._acceptAdmin();
        vm.prank(alice);
        uint256 err = mMockAlpha30._setReserveFactor(0.2e18);
        assertGt(err, 0, "alice should not be mToken admin");
        vm.prank(frank);
        uint256 err2 = mMockAlpha30._setReserveFactor(0.2e18);
        assertEq(err2, 0, "frank should be mToken admin");
    }
}
