// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;
import {Test} from "@forge-std/Test.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";

contract WTAOTest is Test {
    WTAO wtao;
    address alice = makeAddr("alice");

    function setUp() public { wtao = new WTAO(); }

    function test_WTAO_HasCorrectMetadata() public view {
        assertEq(wtao.name(), "Wrapped TAO");
        assertEq(wtao.symbol(), "WTAO");
        assertEq(wtao.decimals(), 18);
    }

    function test_WTAO_MintsAndBurns() public {
        wtao.mint(alice, 50e18);
        assertEq(wtao.balanceOf(alice), 50e18);
        wtao.burn(alice, 20e18);
        assertEq(wtao.balanceOf(alice), 30e18);
    }
}
