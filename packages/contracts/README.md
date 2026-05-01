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
- **EndureDeployHelper.sol**: Atomic deploy helper used by both the Foundry script (`packages/deploy/src/DeployLocal.s.sol`) and the Hardhat script (`packages/contracts/scripts/deploy-local.ts`). Single source of truth for the Endure chassis deployment sequence (Diamond + facets + 3 markets + parameters + seed-and-burn).

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

Local deployment is supported on both toolchains. Both paths use the same `EndureDeployHelper.deployAll()` Solidity logic and produce the same `packages/deploy/addresses.json` (16-key alphabetized schema), so downstream tooling (frontend, integration, keepers) is toolchain-agnostic.

### Foundry path (Anvil)
```bash
anvil --silent --disable-code-size-limit --gas-limit 1000000000 &
cd packages/deploy && forge script src/DeployLocal.s.sol \
    --rpc-url http://localhost:8545 --broadcast --slow --legacy --code-size-limit 999999
bash scripts/e2e-smoke.sh
```
See `packages/deploy/README.md` for details on the EIP-170 size flags.

### Hardhat path (hardhat node)
```bash
pnpm hardhat node                                                            # one terminal
cd packages/contracts && pnpm hardhat run scripts/deploy-local.ts --network localhost
cd packages/contracts && pnpm hardhat run scripts/smoke-local.ts  --network localhost
```
The Hardhat-side deploy targets the in-process `localhost` network and writes the same `packages/deploy/addresses.json`. `scripts/smoke-local.ts` is the Hardhat-native end-to-end smoke (supply/borrow/repay/redeem/liquidation via ethers).

Note: The deployment scripts are not idempotent. Restart the local node before re-running. The vendored Venus `deploy/*.ts` chain is intentionally not auto-run on `hardhat node` startup — see `FORK_MANIFEST.md` §4.3 and §7.
