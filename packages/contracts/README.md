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

## Implementation Notes
- **JumpRateModel**: The "JumpRateModelV2" referenced in roadmap documentation maps to the upstream `JumpRateModel.sol` implementation.
