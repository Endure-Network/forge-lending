// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;
import {Test} from "@forge-std/Test.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {MockAlpha64} from "@protocol/endure/MockAlpha64.sol";

contract MockAlphaTest is Test {
    MockAlpha30 alpha30;
    MockAlpha64 alpha64;
    address alice = makeAddr("alice");

    function setUp() public {
        alpha30 = new MockAlpha30();
        alpha64 = new MockAlpha64();
    }

    function test_MockAlpha30_HasCorrectMetadata() public view {
        assertEq(alpha30.name(), "Mock Alpha 30");
        assertEq(alpha30.symbol(), "mALPHA30");
        assertEq(alpha30.decimals(), 18);
        assertEq(alpha30.netuid(), 30);
    }

    function test_MockAlpha30_MintsToRecipient() public {
        alpha30.mint(alice, 100e18);
        assertEq(alpha30.balanceOf(alice), 100e18);
    }

    function test_MockAlpha30_BurnsFromHolder() public {
        alpha30.mint(alice, 100e18);
        alpha30.burn(alice, 40e18);
        assertEq(alpha30.balanceOf(alice), 60e18);
    }

    function test_MockAlpha64_HasCorrectMetadata() public view {
        assertEq(alpha64.name(), "Mock Alpha 64");
        assertEq(alpha64.symbol(), "mALPHA64");
        assertEq(alpha64.decimals(), 18);
        assertEq(alpha64.netuid(), 64);
    }

    function test_MockAlpha64_MintsToRecipient() public {
        alpha64.mint(alice, 100e18);
        assertEq(alpha64.balanceOf(alice), 100e18);
    }

    function test_MockAlpha64_BurnsFromHolder() public {
        alpha64.mint(alice, 100e18);
        alpha64.burn(alice, 40e18);
        assertEq(alpha64.balanceOf(alice), 60e18);
    }
}
