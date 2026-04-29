# Endure Network Contracts

## Purpose
Endure Network contracts are forked from Venus Protocol Core Pool, stripped and extended for single-chain TAO-only lending on Bittensor EVM. The protocol provides a decentralized lending marketplace optimized for the Bittensor ecosystem.

## Upstream Attribution
This repository is a fork of [VenusProtocol/venus-protocol](https://github.com/VenusProtocol/venus-protocol).
- **License**: BSD-3-Clause
- **Pinned Commit**: `6400a067114a101bd3bebfca2a4bd06480e84831`
- **Tag**: `v10.2.0-dev.5`

See [UPSTREAM.md](UPSTREAM.md) for full vendor details and synchronization policy.

## Architecture
Endure uses the Venus Diamond proxy pattern for the Comptroller:
- **Unitroller**: The entry point proxy.
- **Diamond**: The logic implementation that routes calls to facets.
- **Facets**:
  - **MarketFacet**: Market lifecycle and account liquidity logic.
  - **PolicyFacet**: Policy hooks and risk parameter validation.
  - **SetterFacet**: Admin configuration for markets and protocol globals.
  - **RewardFacet**: Reward distribution logic. RewardFacet is deployed and fully functional. Rewards are opt-in via `enableVenusRewards()`; all reward speeds default to zero. See the protocol README for usage.

## Endure-specific Additions
New contracts and libraries located in `src/endure/`:
- **MockResilientOracle.sol**: Mock oracle implementing `ResilientOracleInterface` for testing.
- **AllowAllAccessControlManager.sol**: Allow-all ACM for testing.
- **DenyAllAccessControlManager.sol**: Deny-all ACM for negative-path tests.
- **MockXVS.sol**: Mock XVS ERC20 for reward path testing.
- **MockAlpha30.sol**, **MockAlpha64.sol**: Phase 0 test ERC20 tokens representing Bittensor subnets.
- **WTAO.sol**: Phase 0 mock Wrapped TAO (borrow asset).
- **EnduRateModelParams.sol**: IRM constants for Venus TwoKinks shape.

## Key Venus Semantics
- **Separate CF/LT**: Collateral Factor and Liquidation Threshold are distinct parameters.
- **Borrow Cap**: A value of 0 means borrowing is DISABLED. Set to `type(uint256).max` for unlimited.
- **Liquidation Incentive**: Set per-market, not globally.
- **Diamond Proxy**: All Comptroller calls go through Unitroller → Diamond → Facets.

## Market Parameters (Phase 0)

| Parameter | vWTAO | vAlpha30 | vAlpha64 |
|-----------|-------|----------|----------|
| Collateral Factor | 0% | 25% | 25% |
| Liquidation Threshold | 0% | 35% | 35% |
| Borrow Cap | unlimited | 0 (blocked) | 0 (blocked) |
| Supply Cap | unlimited | 10,000 | 10,000 |

Only WTAO is borrowable in Phase 0. Alpha markets serve as collateral only.

## Testing
The protocol uses a dual-toolchain test suite:
- **Foundry**: Core protocol and integration tests.
  ```bash
  forge test --root packages/contracts
  ```
- **Hardhat**: Deployment and legacy test infrastructure.
  ```bash
  pnpm hardhat test
  ```

## Deployment
Local deployment to Anvil is handled via Foundry scripts:
```bash
forge script packages/deploy/src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast
```
Note: The deployment script is not idempotent. Restart the local Anvil chain before re-running. See `packages/deploy/README.md` for details.
