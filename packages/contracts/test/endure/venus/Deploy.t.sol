// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
// NOTE: EndureDeployHelperVenus does not exist yet — this import will fail (TDD RED)
import {EndureDeployHelperVenus} from "../../helper/EndureDeployHelperVenus.sol";

contract DeployTest is Test {
    EndureDeployHelperVenus helper;

    function setUp() public {
        helper = new EndureDeployHelperVenus();
    }

    function test_FullAddressSurface() public {
        EndureDeployHelperVenus.VenusAddresses memory addr = helper.deployAll();

        // Core infrastructure
        assertTrue(addr.unitroller != address(0), "unitroller");
        assertTrue(addr.comptrollerLens != address(0), "comptrollerLens");
        assertTrue(addr.accessControlManager != address(0), "accessControlManager");
        assertTrue(addr.resilientOracle != address(0), "resilientOracle");

        // Diamond facets
        assertTrue(addr.marketFacet != address(0), "marketFacet");
        assertTrue(addr.policyFacet != address(0), "policyFacet");
        assertTrue(addr.setterFacet != address(0), "setterFacet");
        assertTrue(addr.rewardFacet != address(0), "rewardFacet");

        // Markets
        assertTrue(addr.vWTAO != address(0), "vWTAO");
        assertTrue(addr.vAlpha30 != address(0), "vAlpha30");
        assertTrue(addr.vAlpha64 != address(0), "vAlpha64");

        // IRMs
        assertTrue(addr.irmWTAO != address(0), "irmWTAO");
        assertTrue(addr.irmAlpha != address(0), "irmAlpha");

        // Underlyings
        assertTrue(addr.wtao != address(0), "wtao");
        assertTrue(addr.mockAlpha30 != address(0), "mockAlpha30");
        assertTrue(addr.mockAlpha64 != address(0), "mockAlpha64");
    }

    function test_ComptrollerWired() public {
        EndureDeployHelperVenus.VenusAddresses memory addr = helper.deployAll();

        // markets listed — Venus markets() returns 7-tuple:
        // (bool isListed, uint256 cf, bool isVenus, uint256 lt, uint256 li, uint96 poolId, bool isBorrowAllowed)
        (bool isListedWTAO,,,,,,) = IComptroller(addr.unitroller).markets(addr.vWTAO);
        assertTrue(isListedWTAO, "vWTAO not listed");

        (bool isListedAlpha30,,,,,,) = IComptroller(addr.unitroller).markets(addr.vAlpha30);
        assertTrue(isListedAlpha30, "vAlpha30 not listed");

        (bool isListedAlpha64,,,,,,) = IComptroller(addr.unitroller).markets(addr.vAlpha64);
        assertTrue(isListedAlpha64, "vAlpha64 not listed");
    }
}

/// @dev Minimal interface to call markets() — Venus 7-field tuple
interface IComptroller {
    function markets(address vToken)
        external
        view
        returns (
            bool isListed,
            uint256 collateralFactorMantissa,
            bool isVenus,
            uint256 liquidationThresholdMantissa,
            uint256 liquidationIncentiveMantissa,
            uint96 poolId,
            bool isBorrowAllowed
        );
}
