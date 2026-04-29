// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelperVenus} from "@test/helper/EndureDeployHelperVenus.sol";
import {VBep20Immutable} from "@protocol/venus-staging/Tokens/VTokens/VBep20Immutable.sol";
import {MarketFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/MarketFacet.sol";
import {MockXVS} from "@protocol/endure/MockXVS.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";
import {WTAO} from "@protocol/endure/WTAO.sol";

/// @title RewardFacetEnableTest
/// @notice Proves the reward enable + claim path works end-to-end via Diamond.
contract RewardFacetEnableTest is Test {
    EndureDeployHelperVenus helper;
    EndureDeployHelperVenus.VenusAddresses addrs;

    MockXVS mockXvs;
    VBep20Immutable vWTAO;
    VBep20Immutable vAlpha30;
    MockAlpha30 mockAlpha30;
    WTAO wtao;

    address alice = makeAddr("alice");
    address supplier = makeAddr("supplier");

    function setUp() public {
        helper = new EndureDeployHelperVenus();
        addrs = helper.deployAll();
        vWTAO = VBep20Immutable(payable(addrs.vWTAO));
        vAlpha30 = VBep20Immutable(payable(addrs.vAlpha30));
        mockAlpha30 = MockAlpha30(addrs.mockAlpha30);
        wtao = WTAO(addrs.wtao);
        mockXvs = new MockXVS();

        // Fund MockXVS and approve helper to transfer
        mockXvs.mint(address(this), 1_000e18);
        mockXvs.approve(address(helper), 1_000e18);

        // Enable rewards: vWTAO gets supply speed 1e18, borrow speed 0
        address[] memory vTokens = new address[](1);
        vTokens[0] = addrs.vWTAO;
        uint256[] memory supplySpeeds = new uint256[](1);
        supplySpeeds[0] = 1e18;
        uint256[] memory borrowSpeeds = new uint256[](1);
        borrowSpeeds[0] = 0;

        helper.enableVenusRewards(address(mockXvs), vTokens, supplySpeeds, borrowSpeeds, 1_000e18);
    }

    /// @notice After enableVenusRewards, venusSupplySpeeds returns the configured speed.
    function test_SupplySpeedConfigured() public view {
        (bool ok, bytes memory data) =
            addrs.unitroller.staticcall(abi.encodeWithSignature("venusSupplySpeeds(address)", addrs.vWTAO));
        require(ok, "venusSupplySpeeds call failed");
        uint256 speed = abi.decode(data, (uint256));
        assertEq(speed, 1e18, "supply speed should be 1e18");
    }

    /// @notice getXVSAddress returns the registered mock XVS token.
    function test_GetXVSAddress() public view {
        (bool ok, bytes memory data) =
            addrs.unitroller.staticcall(abi.encodeWithSignature("getXVSAddress()"));
        require(ok, "getXVSAddress call failed");
        address xvsAddr = abi.decode(data, (address));
        assertEq(xvsAddr, address(mockXvs), "getXVSAddress should return mock XVS");
    }

    /// @notice Alice supplies, time-warps, claims Venus rewards.
    function test_ClaimVenusRewards() public {
        // Alice supplies WTAO to earn rewards
        wtao.mint(alice, 100e18);
        vm.startPrank(alice);
        wtao.approve(address(vWTAO), 100e18);
        assertEq(vWTAO.mint(100e18), 0, "alice mint vWTAO");
        vm.stopPrank();

        // Time-warp to accrue rewards
        vm.roll(block.number + 100);

        // Alice claims
        (bool ok,) = addrs.unitroller.call(abi.encodeWithSignature("claimVenus(address)", alice));
        require(ok, "claimVenus failed");

        // Alice should have received some mock XVS
        assertGt(mockXvs.balanceOf(alice), 0, "alice should have received XVS rewards");
    }
}
