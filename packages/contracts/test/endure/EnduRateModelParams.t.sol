// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import {Test} from "@forge-std/Test.sol";
import {EnduRateModelParamsVenus} from "@protocol/endure/EnduRateModelParams.sol";
import {TwoKinksInterestRateModel} from "@protocol/venus-staging/InterestRateModels/TwoKinksInterestRateModel.sol";

contract EnduRateModelParamsTest is Test {
    /// @notice Verify TwoKinksInterestRateModel constructs with Venus 8-param int256 shape.
    function test_VenusTwoKinksIRMConstructsFromParams() public {
        TwoKinksInterestRateModel irm = new TwoKinksInterestRateModel(
            EnduRateModelParamsVenus.WTAO_BASE_RATE_PER_YEAR,
            EnduRateModelParamsVenus.WTAO_MULTIPLIER_PER_YEAR,
            EnduRateModelParamsVenus.WTAO_KINK1,
            EnduRateModelParamsVenus.WTAO_MULTIPLIER_2_PER_YEAR,
            EnduRateModelParamsVenus.WTAO_BASE_RATE_2_PER_YEAR,
            EnduRateModelParamsVenus.WTAO_KINK2,
            EnduRateModelParamsVenus.WTAO_JUMP_MULTIPLIER_PER_YEAR,
            EnduRateModelParamsVenus.BLOCKS_PER_YEAR
        );

        // IRM deploys and is callable — zero utilization returns base rate
        uint256 borrowRate = irm.getBorrowRate(1_000e18, 0, 0);
        assertGt(borrowRate, 0, "base rate should be non-zero for WTAO");
    }

    /// @notice Alpha IRM has zero rates (collateral-only, borrowing disabled).
    function test_VenusAlphaIRMIsZeroRate() public {
        TwoKinksInterestRateModel irm = new TwoKinksInterestRateModel(
            EnduRateModelParamsVenus.ALPHA_BASE_RATE_PER_YEAR,
            EnduRateModelParamsVenus.ALPHA_MULTIPLIER_PER_YEAR,
            EnduRateModelParamsVenus.ALPHA_KINK1,
            EnduRateModelParamsVenus.ALPHA_MULTIPLIER_2_PER_YEAR,
            EnduRateModelParamsVenus.ALPHA_BASE_RATE_2_PER_YEAR,
            EnduRateModelParamsVenus.ALPHA_KINK2,
            EnduRateModelParamsVenus.ALPHA_JUMP_MULTIPLIER_PER_YEAR,
            EnduRateModelParamsVenus.BLOCKS_PER_YEAR
        );

        uint256 borrowRate = irm.getBorrowRate(1_000e18, 500e18, 0);
        assertEq(borrowRate, 0, "alpha IRM should be zero-rate");
    }
}
