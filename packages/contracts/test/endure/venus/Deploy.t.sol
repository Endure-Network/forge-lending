// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelperVenus} from "../../helper/EndureDeployHelperVenus.sol";
import {VBep20Immutable} from "@protocol/venus-staging/Tokens/VTokens/VBep20Immutable.sol";

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

    function test_CFReturnCodeZero() public {
        EndureDeployHelperVenus.VenusAddresses memory addr = helper.deployAll();

        (, uint256 wtaoCf,, uint256 wtaoLt,,, bool wtaoBorrowAllowed) = IComptroller(addr.unitroller).markets(addr.vWTAO);
        assertEq(wtaoCf, 0, "vWTAO collateral factor");
        assertEq(wtaoLt, 0, "vWTAO liquidation threshold");
        assertTrue(wtaoBorrowAllowed, "vWTAO borrow not enabled");

        (, uint256 alpha30Cf,, uint256 alpha30Lt,,, bool alpha30BorrowAllowed) = IComptroller(addr.unitroller).markets(addr.vAlpha30);
        assertEq(alpha30Cf, 0.25e18, "vAlpha30 collateral factor");
        assertEq(alpha30Lt, 0.35e18, "vAlpha30 liquidation threshold");
        assertFalse(alpha30BorrowAllowed, "vAlpha30 borrow enabled");

        (, uint256 alpha64Cf,, uint256 alpha64Lt,,, bool alpha64BorrowAllowed) = IComptroller(addr.unitroller).markets(addr.vAlpha64);
        assertEq(alpha64Cf, 0.25e18, "vAlpha64 collateral factor");
        assertEq(alpha64Lt, 0.35e18, "vAlpha64 liquidation threshold");
        assertFalse(alpha64BorrowAllowed, "vAlpha64 borrow enabled");
    }

    function test_BorrowCapsAndSeedBurnConfigured() public {
        EndureDeployHelperVenus.VenusAddresses memory addr = helper.deployAll();

        assertEq(IComptroller(addr.unitroller).borrowCaps(addr.vWTAO), type(uint256).max, "vWTAO borrow cap");
        assertEq(IComptroller(addr.unitroller).borrowCaps(addr.vAlpha30), 0, "vAlpha30 borrow cap");
        assertEq(IComptroller(addr.unitroller).borrowCaps(addr.vAlpha64), 0, "vAlpha64 borrow cap");

        assertEq(IOracle(addr.resilientOracle).getUnderlyingPrice(addr.vWTAO), 1e18, "vWTAO oracle price");
        assertEq(IOracle(addr.resilientOracle).getUnderlyingPrice(addr.vAlpha30), 1e18, "vAlpha30 oracle price");
        assertEq(IOracle(addr.resilientOracle).getUnderlyingPrice(addr.vAlpha64), 1e18, "vAlpha64 oracle price");

        assertGt(VBep20Immutable(payable(addr.vWTAO)).totalSupply(), 0, "vWTAO total supply");
        assertGt(VBep20Immutable(payable(addr.vAlpha30)).totalSupply(), 0, "vAlpha30 total supply");
        assertGt(VBep20Immutable(payable(addr.vAlpha64)).totalSupply(), 0, "vAlpha64 total supply");

        assertGt(VBep20Immutable(payable(addr.vWTAO)).balanceOf(address(0xdEaD)), 0, "vWTAO dead balance");
        assertGt(VBep20Immutable(payable(addr.vAlpha30)).balanceOf(address(0xdEaD)), 0, "vAlpha30 dead balance");
        assertGt(VBep20Immutable(payable(addr.vAlpha64)).balanceOf(address(0xdEaD)), 0, "vAlpha64 dead balance");
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

    function borrowCaps(address vToken) external view returns (uint256);
}

interface IOracle {
    function getUnderlyingPrice(address vToken) external view returns (uint256);
}
