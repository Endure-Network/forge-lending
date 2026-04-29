// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EndureDeployHelper} from "@protocol/endure/EndureDeployHelper.sol";
import {VBep20Immutable} from "@protocol/Tokens/VTokens/VBep20Immutable.sol";
import {VToken} from "@protocol/Tokens/VTokens/VToken.sol";
import {ComptrollerInterface} from "@protocol/Comptroller/ComptrollerInterface.sol";
import {InterestRateModelV8} from "@protocol/InterestRateModels/InterestRateModelV8.sol";
import {MarketFacet} from "@protocol/Comptroller/Diamond/facets/MarketFacet.sol";
import {SetterFacet} from "@protocol/Comptroller/Diamond/facets/SetterFacet.sol";
import {MockResilientOracle} from "@protocol/endure/MockResilientOracle.sol";
import {MockAlpha30} from "@protocol/endure/MockAlpha30.sol";

/// @title CollateralFactorOrderingTest
/// @notice Proves Venus rejects invalid CF/LT configurations.
contract CollateralFactorOrderingTest is Test {
    EndureDeployHelper helper;
    EndureDeployHelper.Addresses addrs;

    SetterFacet sf;

    function setUp() public {
        helper = new EndureDeployHelper();
        addrs = helper.deployAll();
        sf = SetterFacet(addrs.unitroller);
    }

    /// @notice setCollateralFactor rejects LT < CF (returns non-zero error code).
    function test_RejectsLTBelowCF() public {
        // Try to set CF=0.6 with LT=0.5 (LT < CF is invalid)
        uint256 err = sf.setCollateralFactor(VToken(addrs.vAlpha30), 0.6e18, 0.5e18);
        assertGt(err, 0, "setCollateralFactor must reject LT < CF");

        // Verify existing values unchanged
        (bool ok, bytes memory data) =
            addrs.unitroller.staticcall(abi.encodeWithSignature("markets(address)", addrs.vAlpha30));
        require(ok, "markets() call failed");
        (, uint256 cf,, uint256 lt,,,) = abi.decode(data, (bool, uint256, bool, uint256, uint256, uint96, bool));
        assertEq(cf, 0.25e18, "CF should not mutate");
        assertEq(lt, 0.35e18, "LT should not mutate");
    }

    /// @notice setCollateralFactor rejects if oracle returns zero price for market.
    function test_RejectsUnsetOracle() public {
        // Deploy a fresh underlying with no oracle price
        MockAlpha30 newUnderlying = new MockAlpha30();
        VBep20Immutable newVToken = new VBep20Immutable(
            address(newUnderlying),
            ComptrollerInterface(addrs.unitroller),
            InterestRateModelV8(addrs.irmAlpha),
            1e18,
            "Test No Price",
            "vNOPRICE",
            8,
            payable(address(helper))
        );

        // Support the market (admin = helper)
        vm.prank(address(helper));
        require(
            MarketFacet(addrs.unitroller)._supportMarket(VToken(address(newVToken))) == 0,
            "support market"
        );

        // No oracle price set — setCollateralFactor should fail
        uint256 err = sf.setCollateralFactor(VToken(address(newVToken)), 0.25e18, 0.35e18);
        assertGt(err, 0, "setCollateralFactor must reject when oracle returns zero price");
    }
}
