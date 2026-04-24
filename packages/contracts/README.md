# Endure Network Contracts

## Purpose
Endure Network contracts are forked from Moonwell v2, stripped and extended for single-chain TAO-only lending. The protocol provides a decentralized lending marketplace optimized for the Bittensor ecosystem.

## Upstream Attribution
This repository is a fork of [moonwell-fi/moonwell-contracts-v2](https://github.com/moonwell-fi/moonwell-contracts-v2).
- **License**: BSD-3-Clause
- **Pinned Commit**: 8d5fb1107babf7935cfabc2f6ecdb1722547f085
See [UPSTREAM.md](UPSTREAM.md) for full vendor details and synchronization policy.

## Endure-specific Additions
New contracts and libraries located in `src/endure/`:
- **MockAlpha30.sol**, **MockAlpha64.sol**: Phase 0 test ERC20 tokens representing Bittensor subnets (netuid 30 and 64) with 18 decimals.
- **WTAO.sol**: Phase 0 mock Wrapped TAO implementation.
- **MockPriceOracle.sol**: Simplified admin-set oracle for Phase 0. Supports one-step admin transfer.
- **EndureRoles.sol**: Library defining `RoleSet` struct to bundle protocol roles (Admin, Pause Guardian, Borrow Cap Guardian, Supply Cap Guardian). This is a structural grouping, not a multisig implementation.
- **EnduRateModelParams.sol**: Centralized store for Endure Interest Rate Model and market parameter constants.

## Admin Model (Phase 0)
The deployment process assigns the Deployer EOA as the admin for all core contracts:
- Unitroller (Comptroller)
- MTokens
- MockPriceOracle
- Interest Rate Models

Guardians (Pause, Borrow Cap, Supply Cap) default to the deployer address but are overridable via environment variables during deployment. Phase 4 will introduce formal governance via Timelock and GovernorBravo. No custom multisig code is included in Phase 0.

## Stripped from Upstream
The following components were removed to simplify the protocol for single-chain deployment:
- **Governance**: TemporalGovernor, Wormhole bridge components, Well token (WELL/xWELL), and associated staking modules (stkWell).
- **Rewards**: MultiRewardDistributor (Note: base storage classes were retained to maintain Comptroller storage layout).
- **Integrations**: Morpho blue integrations and specialized views.
- **Sale**: Token sale and vesting contracts.

## Configuration Divergences
- **EVM Version**: `shanghai` (Upstream uses `cancun`).
- **Optimization**: `optimizer_runs = 200`.
- **Invariants**: Configured for `runs = 1000`, `depth = 50`.
- **RPC**: No external RPC endpoints are defined in `foundry.toml`.

## Phase 0 Scope
- No Bittensor cross-chain logic.
- Mock WTAO (no actual wrapping of TAO).
- No integration with Chainlink (using MockPriceOracle).
- No automated liquidator bot.
- Local/Anvil deployment focus.

## Testing
Execute the test suite using Foundry:
```bash
forge test --root packages/contracts
```
The suite includes 9 primary test categories including unit tests for added contracts, integration tests for deployment, and invariant tests for core protocol safety.

## Deployment
Local deployment to Anvil is handled via the scripts in `packages/deploy/`.
```bash
# From workspace root
npm run deploy:local
```
Note: The Phase 0 deployment script is not idempotent. Restart the local Anvil chain before re-running. See `packages/deploy/README.md` for details.

## Market Parameters (Phase 0)

| Parameter | mWTAO | mMockAlpha30 | mMockAlpha64 |
|-----------|-------|--------------|--------------|
| Collateral Factor | 0% | 25% | 25% |
| Borrow Cap | unlimited | 1 wei (blocked) | 1 wei (blocked) |
| Supply Cap | unlimited | 10,000 tokens | 10,000 tokens |
| Reserve Factor | 15% | 15% | 15% |

Only WTAO is borrowable in Phase 0. Alpha markets serve as collateral only.

## Interest Rate Model (mWTAO)

JumpRateModel with:
- Base rate: 2% per year
- Multiplier: 10% per year (to kink)
- Jump multiplier: 300% per year (above kink)
- Kink: 80% utilization

Alpha markets use zero-rate IRM (borrowing disabled via borrow cap = 1 wei).

## Seed Deposits

Every market receives a seed deposit of `1e18` (1 whole token) at listing time. The resulting mTokens are burned to `address(0xdEaD)` to prevent empty-market donation attacks. This is verified by `test_EveryMarketHasPositiveTotalSupply` and `test_DeadAddressHoldsSeedMTokens`.

## Test Suites

| Suite | File | Tests |
|-------|------|-------|
| MockAlpha unit | `test/endure/MockAlpha.t.sol` | 6 |
| WTAO unit | `test/endure/WTAO.t.sol` | 2 |
| MockPriceOracle unit | `test/endure/MockPriceOracle.t.sol` | 7 |
| EnduRateModelParams | `test/endure/EnduRateModelParams.t.sol` | 1 |
| RBAC separation | `test/endure/RBACSeparation.t.sol` | 7 |
| Alice lifecycle | `test/endure/integration/AliceLifecycle.t.sol` | 1 |
| Liquidation + negatives | `test/endure/integration/Liquidation.t.sol` | 3 |
| Seed deposit + negatives | `test/endure/SeedDeposit.t.sol` | 5 |
| Invariant solvency | `test/endure/invariant/InvariantSolvency.t.sol` | 2 (1000 runs × 50 depth) |

Run all: `forge test --root packages/contracts`

## Gas Snapshot

A committed gas snapshot is maintained at `.gas-snapshot`. CI enforces no regressions:

```bash
scripts/gas-snapshot-check.sh
```

To update after intentional gas changes: `forge snapshot --root packages/contracts`

## Known Phase 0 Limitations

- Deploy script is **not idempotent** — requires fresh Anvil per run
- No real Chainlink oracle wiring (ChainlinkOracle.sol kept as reference only)
- No native TAO wrap semantics (WTAO is a plain ERC20 mock)
- No Timelock or GovernorBravo (Phase 4)
- No Gnosis Safe or multisig (Phase 1/2)

## Implementation Notes

- **JumpRateModel**: The "JumpRateModelV2" referenced in roadmap documentation maps to the upstream `JumpRateModel.sol` implementation.
- **MultiRewardDistributor**: Kept in `src/rewards/` as a Stance B exception — `ComptrollerStorage.sol` imports it and cannot be modified without breaking upstream backport discipline.
- **Stance B**: All kept Moonwell `.sol` files under `src/` are byte-identical to upstream commit `8d5fb11`. See `FORK_MANIFEST.md` for the full audit trail.
