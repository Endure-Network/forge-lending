// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelperVenus} from "@test/helper/EndureDeployHelperVenus.sol";
import {VBep20Immutable} from "@protocol/venus-staging/Tokens/VTokens/VBep20Immutable.sol";
import {VToken} from "@protocol/venus-staging/Tokens/VTokens/VToken.sol";
import {Unitroller} from "@protocol/venus-staging/Comptroller/Unitroller.sol";
import {SetterFacet} from "@protocol/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol";
import {DenyAllAccessControlManager} from "@protocol/endure/DenyAllAccessControlManager.sol";

contract RBACSeparationTest is Test {
    EndureDeployHelperVenus helper;
    EndureDeployHelperVenus.VenusAddresses addrs;

    SetterFacet sf;
    DenyAllAccessControlManager denyAcm;
    address nonAdmin = makeAddr("nonAdmin");

    function setUp() public {
        helper = new EndureDeployHelperVenus();
        addrs = helper.deployAll();
        sf = SetterFacet(addrs.unitroller);
        denyAcm = new DenyAllAccessControlManager();
    }

    /// @notice With AllowAll ACM, setMarketBorrowCaps succeeds for anyone.
    function test_AllowAllACM_SetBorrowCapsSucceeds() public {
        VToken[] memory markets = new VToken[](1);
        markets[0] = VToken(addrs.vAlpha30);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 5_000e18;

        // Anyone can call — AllowAll ACM permits everything
        sf.setMarketBorrowCaps(markets, caps);
    }

    /// @notice Hot-swap to DenyAll ACM blocks previously-allowed operations.
    function test_DenyAllACM_SetBorrowCapsRejected() public {
        // Hot-swap ACM to DenyAll (must be called by admin = helper)
        vm.prank(address(helper));
        sf._setAccessControl(address(denyAcm));

        VToken[] memory markets = new VToken[](1);
        markets[0] = VToken(addrs.vAlpha30);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 5_000e18;

        // DenyAll ACM rejects the call — Venus reverts on ACM failure
        vm.expectRevert("access denied");
        sf.setMarketBorrowCaps(markets, caps);
    }

    /// @notice Non-deployer cannot call admin-only _setPendingImplementation
    ///         even with AllowAll ACM (admin check is independent of ACM).
    function test_AdminBypass_NonAdminCannotSetPendingImpl() public {
        vm.prank(nonAdmin);
        uint256 err = Unitroller(payable(addrs.unitroller))._setPendingImplementation(nonAdmin);
        assertGt(err, 0, "non-admin should fail _setPendingImplementation");
    }
}
