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
