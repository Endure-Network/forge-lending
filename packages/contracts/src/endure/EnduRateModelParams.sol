// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

library EnduRateModelParams {
    uint256 internal constant WTAO_BASE_RATE_PER_YEAR = 0.02e18;
    uint256 internal constant WTAO_MULTIPLIER_PER_YEAR = 0.10e18;
    uint256 internal constant WTAO_JUMP_MULTIPLIER_PER_YEAR = 3e18;
    uint256 internal constant WTAO_KINK = 0.80e18;

    uint256 internal constant ALPHA_BASE_RATE_PER_YEAR = 0;
    uint256 internal constant ALPHA_MULTIPLIER_PER_YEAR = 0;
    uint256 internal constant ALPHA_JUMP_MULTIPLIER_PER_YEAR = 0;
    uint256 internal constant ALPHA_KINK = 1e18;

    uint256 internal constant CLOSE_FACTOR = 0.5e18;
    uint256 internal constant LIQUIDATION_INCENTIVE = 1.08e18;
    uint256 internal constant COLLATERAL_FACTOR_ALPHA = 0.25e18;
    uint256 internal constant COLLATERAL_FACTOR_WTAO = 0;
    uint256 internal constant SUPPLY_CAP_ALPHA = 10_000e18;
    uint256 internal constant BORROW_CAP_ALPHA = 1;
    uint256 internal constant BORROW_CAP_WTAO = type(uint256).max;
    uint256 internal constant RESERVE_FACTOR = 0.15e18;
    uint256 internal constant SEED_AMOUNT = 1e18;
    uint256 internal constant INITIAL_EXCHANGE_RATE_MANTISSA = 2e18;
}
