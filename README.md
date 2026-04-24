# Endure Network

Endure is a lending protocol built as a Moonwell v2 fork, targeting EVM-compatible chains. This monorepo houses all components — Solidity contracts, deployment scripts, TypeScript SDK, frontend, and keeper bots — organized as a pnpm workspace. Phase 0 focuses on forking Moonwell v2 contracts and standing up a local Anvil deployment with mock ERC20 collaterals.

## Packages

| Package | Description |
|---------|-------------|
| `packages/contracts` | Solidity smart contracts (Foundry) |
| `packages/deploy` | Deployment scripts and address registry |
| `packages/sdk` | TypeScript SDK for protocol interaction |
| `packages/frontend` | Web frontend |
| `packages/keeper` | Keeper / liquidation bots |

See [`packages/contracts/README.md`](packages/contracts/README.md) for contract-specific documentation.
