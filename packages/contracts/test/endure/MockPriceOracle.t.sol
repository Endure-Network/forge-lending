// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {MockPriceOracle} from "@protocol/endure/MockPriceOracle.sol";
import {MToken} from "@protocol/MToken.sol";

contract MockPriceOracleTest is Test {
    MockPriceOracle oracle;
    address admin;
    address bob = makeAddr("bob");
    MToken fakeMToken;

    function setUp() public {
        admin = address(this);
        oracle = new MockPriceOracle();
        fakeMToken = MToken(makeAddr("mToken"));
    }

    function test_SetAndGetPrice() public {
        oracle.setUnderlyingPrice(fakeMToken, 1e18);
        assertEq(oracle.getUnderlyingPrice(fakeMToken), 1e18);
    }

    function test_OnlyAdminCanSetPrice() public {
        vm.prank(bob);
        vm.expectRevert("only admin");
        oracle.setUnderlyingPrice(fakeMToken, 1e18);
    }

    function test_ZeroPriceOnRead() public view {
        assertEq(oracle.getUnderlyingPrice(fakeMToken), 0);
    }

    function test_ConstructorSetsAdmin() public view {
        assertEq(oracle.admin(), address(this));
    }

    function test_SetAdminHandsOff() public {
        oracle.setAdmin(bob);
        assertEq(oracle.admin(), bob);
        vm.prank(address(this));
        vm.expectRevert("only admin");
        oracle.setUnderlyingPrice(fakeMToken, 2e18);
        vm.prank(bob);
        oracle.setUnderlyingPrice(fakeMToken, 2e18);
        assertEq(oracle.getUnderlyingPrice(fakeMToken), 2e18);
    }

    function test_OnlyAdminCanSetAdmin() public {
        vm.prank(bob);
        vm.expectRevert("only admin");
        oracle.setAdmin(bob);
    }

    function test_SetAdminZeroAddressReverts() public {
        vm.expectRevert("new admin = 0");
        oracle.setAdmin(address(0));
    }
}
