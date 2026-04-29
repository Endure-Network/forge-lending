# Endure Network

Endure is a lending protocol built as a Venus Protocol Core Pool fork, targeting EVM-compatible chains. This monorepo houses all components — Solidity contracts, deployment scripts, TypeScript SDK, frontend, and keeper bots — organized as a pnpm workspace. Phase 0.5 focuses on rebasing the protocol onto the Venus Diamond proxy architecture.

## Packages

| Package | Description |
|---------|-------------|
| `packages/contracts` | Solidity smart contracts (Foundry + Hardhat) |
| `packages/deploy` | Deployment scripts and address registry |
| `packages/sdk` | TypeScript SDK for protocol interaction |
| `packages/frontend` | Web frontend |
| `packages/keeper` | Keeper / liquidation bots |

See [`packages/contracts/README.md`](packages/contracts/README.md) for contract-specific documentation.

## Venus-specific Footguns

- **borrow cap 0 = DISABLED**: Unlike Moonwell where 0 often means unlimited, in Venus it means borrowing is blocked. Set to `type(uint256).max` for unlimited.
- **setCollateralFactor**: Has NO leading underscore (unlike Moonwell's `_setCollateralFactor`).
- **setLiquidationIncentive**: Set PER-MARKET (not global).
- **Oracle prices MUST be set BEFORE CF/LT**: Ordering constraint in the policy facet.
- **setIsBorrowAllowed required**: Explicitly required to enable borrowing on a market.
- **markets() returns 7-tuple**: Not a 3-tuple. Decode all 7 fields correctly.
- **Diamond proxy**: All Comptroller calls go through Unitroller proxy → Diamond → facets.

