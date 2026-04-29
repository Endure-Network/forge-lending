# Phase 0.5 Venus Rebase — Behavior Mapping Table

This table maps every deleted Phase 0 Endure test to its Venus replacement test, preserving behavior coverage through the rebase.

CI enforcement: `scripts/check-test-mapping.sh` fails if any deleted test path lacks a row here.

| Phase 0 test path | Behavior asserted | Venus replacement test path | Notes |
|---|---|---|---|
| test/endure/integration/AliceLifecycle.t.sol | Supply alpha, borrow WTAO, repay, redeem full lifecycle | test/endure/integration/AliceLifecycle.t.sol (ported) | Same file path, Venus chassis |
| test/endure/integration/Liquidation.t.sol | Price-drop liquidation + healthy account negative | test/endure/integration/Liquidation.t.sol (ported) | LT-vs-CF separation added |
| test/endure/SeedDeposit.t.sol | Every market has positive totalSupply + dead-address seed | test/endure/SeedDeposit.t.sol (ported) | vToken API |
| test/endure/RBACSeparation.t.sol | Moonwell guardian/admin role separation | test/endure/RBACSeparation.t.sol (ported) | Venus ACM-gated roles |
| test/endure/EnduRateModelParams.t.sol | IRM constants match TwoKinks constructor | test/endure/EnduRateModelParams.t.sol (ported) | 8-param int256 shape |
| test/endure/MockAlpha.t.sol | MockAlpha30/64 ERC20 behavior | test/endure/MockAlpha.t.sol (unchanged) | Minimal changes |
| test/endure/WTAO.t.sol | WTAO mock ERC20 behavior | test/endure/WTAO.t.sol (unchanged) | Minimal changes |
| test/endure/MockPriceOracle.t.sol | Phase 0 MockPriceOracle unit tests | DELETED — replaced by Venus oracle behavior | MockResilientOracle covers oracle behavior; Venus-specific oracle tests in Lifecycle.t.sol |
| test/endure/invariant/InvariantSolvency.t.sol | Protocol solvency invariant 1000×50 | test/endure/invariant/InvariantSolvency.t.sol (ported) | Venus chassis; same depth/runs |
| *(net-new)* | LT vs CF separation: gap zone safe, past LT liquidatable | test/endure/venus/LiquidationThreshold.t.sol | Venus-specific LT/CF semantics |
| *(net-new)* | setCollateralFactor rejects LT<CF and zero-oracle markets | test/endure/venus/CollateralFactorOrdering.t.sol | Venus-specific CF ordering |
| *(net-new)* | borrowCap=max → unlimited; borrowCap=0 → disabled | test/endure/venus/BorrowCapSemantics.t.sol | Venus cap=0 disables (differs from Compound) |
| *(net-new)* | Reward enable via Diamond proxy + claimVenus e2e | test/endure/venus/RewardFacetEnable.t.sol | Requires MockXVS.sol |
| test/endure/venus/VenusDirectLiquidationSpike.t.sol | Stage A spike: selectors, lifecycle, direct liquidation | test/endure/venus/Lifecycle.t.sol (renamed) | Redundant tests removed; 5 core tests kept |
| test/unit/Comptroller.t.sol | Monolithic Comptroller unit tests | test/endure/venus/DiamondSelectorRouting.t.sol, test/endure/Deploy.t.sol, test/endure/venus/CollateralFactorOrdering.t.sol | Venus Diamond replaces monolithic Comptroller |
| test/unit/MErc20.t.sol | MErc20 token unit tests | test/endure/integration/Lifecycle.t.sol, test/endure/integration/AliceLifecycle.t.sol | VBep20Immutable replaces MErc20 |
| test/unit/MErc20Delegate.t.sol | MErc20Delegate upgrade pattern tests | NOT APPLICABLE | Venus uses VBep20Immutable — no delegate pattern |
| test/unit/Oracle.t.sol | ChainlinkCompositeOracle unit tests | test/endure/integration/Lifecycle.t.sol (oracle reads exercised) | ChainlinkCompositeOracle removed; Venus uses ResilientOracleInterface; Endure uses MockResilientOracle |
