// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@protocol/endure/EndureDeployHelper.sol";
import {MockXVS} from "@protocol/endure/MockXVS.sol";

contract XVSRewardsOptionalTest is Test {
    EndureDeployHelper helper;
    EndureDeployHelper.Addresses addrs;
    MockXVS xvs;

    function setUp() public {
        helper = new EndureDeployHelper();
        addrs = helper.deployAll();
        xvs = new MockXVS();
    }

    function test_EnableXVSRewards_SetsSpeedsAndFundsComptroller() public {
        address[] memory markets = new address[](1);
        markets[0] = addrs.vWTAO;

        uint256[] memory supplySpeeds = new uint256[](1);
        supplySpeeds[0] = 1e18;

        uint256[] memory borrowSpeeds = new uint256[](1);
        borrowSpeeds[0] = 2e18;

        xvs.mint(address(this), 100e18);
        xvs.approve(address(helper), 100e18);

        helper.enableVenusRewards(address(xvs), markets, supplySpeeds, borrowSpeeds, 100e18);

        assertEq(_readUint(addrs.unitroller, "venusSupplySpeeds(address)", addrs.vWTAO), 1e18);
        assertEq(_readUint(addrs.unitroller, "venusBorrowSpeeds(address)", addrs.vWTAO), 2e18);
        assertEq(_readAddress(addrs.unitroller, "getXVSAddress()"), address(xvs));
        assertEq(xvs.balanceOf(addrs.unitroller), 100e18);
    }

    function _readUint(address target, string memory signature, address arg) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature(signature, arg));
        require(ok, "uint read failed");
        value = abi.decode(data, (uint256));
    }

    function _readAddress(address target, string memory signature) internal view returns (address value) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature(signature));
        require(ok, "address read failed");
        value = abi.decode(data, (address));
    }
}
