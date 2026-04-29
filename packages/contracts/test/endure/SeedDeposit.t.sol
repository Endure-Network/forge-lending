// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelperVenus} from "@test/helper/EndureDeployHelperVenus.sol";
import {VBep20Immutable} from "@protocol/venus-staging/Tokens/VTokens/VBep20Immutable.sol";

contract SeedDepositTest is Test {
    EndureDeployHelperVenus helper;
    EndureDeployHelperVenus.VenusAddresses addrs;

    VBep20Immutable vWTAO;
    VBep20Immutable vAlpha30;
    VBep20Immutable vAlpha64;

    address constant DEAD = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        helper = new EndureDeployHelperVenus();
        addrs = helper.deployAll();
        vWTAO = VBep20Immutable(payable(addrs.vWTAO));
        vAlpha30 = VBep20Immutable(payable(addrs.vAlpha30));
        vAlpha64 = VBep20Immutable(payable(addrs.vAlpha64));
    }

    function test_EveryMarketHasPositiveTotalSupply() public view {
        assertGe(vWTAO.totalSupply(), 1e18, "vWTAO totalSupply < 1e18");
        assertGe(vAlpha30.totalSupply(), 1e18, "vAlpha30 totalSupply < 1e18");
        assertGe(vAlpha64.totalSupply(), 1e18, "vAlpha64 totalSupply < 1e18");
    }

    function test_DeadAddressHoldsSeedVTokens() public view {
        assertGt(vWTAO.balanceOf(DEAD), 0, "vWTAO dEaD balance == 0");
        assertGt(vAlpha30.balanceOf(DEAD), 0, "vAlpha30 dEaD balance == 0");
        assertGt(vAlpha64.balanceOf(DEAD), 0, "vAlpha64 dEaD balance == 0");
    }
}
