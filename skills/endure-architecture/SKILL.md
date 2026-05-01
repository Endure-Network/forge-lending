---
name: endure-architecture
description: "Use on every Endure Network task to ground decisions in locked architectural choices. Triggers on mentions of Endure, Endure Network, Endure Subnet, Endure Vault, lending protocol, vault, Phase 0-4 (any of them), monorepo layout, package structure, pooled collateral, TAO-only, Bittensor EVM lending, alpha collateral, MAlpha, MTao, EnduOracle, BittensorStakeAdapter, hotkey topology, Venus chassis, Diamond proxy."
---

# Endure Network — Locked Architecture

This skill encodes the decisions that have been made. If a task seems to require re-litigating any of these, surface the conflict rather than silently deviating.

## What Endure is

A pooled-collateral, TAO-only lending protocol on Bittensor EVM. Users deposit alpha tokens (from Bittensor subnet AMMs) as collateral, borrow TAO against a combined account health factor. Forked from Venus Protocol Core Pool for the lending core; custody and oracle are Endure-new.

Separate from the **Endure Subnet** (SN30), which is a risk oracle subnet. The subnet feeds parameters into the lending protocol but is a distinct concern.

**One-line**: A pooled-collateral, TAO-only lending protocol on Bittensor EVM, forked from Venus Protocol Core Pool with Bittensor-native custody and oracle adapters.

## Locked decisions

### 1. Chassis: Venus Protocol fork

- Repo: `VenusProtocol/venus-protocol`
- License: BSD-3-Clause
- Solidity: 0.8.25
- Build: Foundry + Hardhat
- Architecture: Diamond proxy pattern (Unitroller → Diamond → Facets)
- Reason over alternatives: Separate CF/LT, Diamond architecture for upgradeability, battle-tested Core Pool logic.

### 2. Borrow asset: TAO only

- Single base borrowable asset (vWTAO)
- Alpha markets are collateral-only (borrow cap set to 0)
- Simplifies oracle to TAO-denominated HF
- Simplifies liquidation to single alpha→TAO path

### 3. Collateral model: pooled multi-collateral

- Users deposit basket of alpha across different netuids into one account
- Single HF computed across the basket
- Per-market collateral factors, liquidation thresholds, supply caps, and borrow caps do the risk work

### 4. Key Contracts

- **Unitroller**: Entry point proxy
- **Diamond**: Logic routing to facets
- **Facets**: MarketFacet, PolicyFacet, SetterFacet, RewardFacet
- **ComptrollerLens**: View functions for protocol state
- **ACM (Access Control Manager)**: Gated function access
- **ResilientOracle**: Multi-source oracle system

### 5. Market Structure

- **vWTAO**: The borrow asset. CF=0, LT=0.
- **vAlpha30 / vAlpha64**: Collateral assets. CF=0.25, LT=0.35.

### 6. Venus Semantics

- **Borrow cap 0 = DISABLED**: Not unlimited like Moonwell.
- **setCollateralFactor**: No leading underscore.
- **setLiquidationIncentive**: Set per-market.
- **Ordering**: Oracle prices must be set before CF/LT.

### 7. Off-chain language: TypeScript everywhere

- SDK (`packages/sdk`): Wraps protocol interactions.
- Frontend (`packages/frontend`): Next.js.
- Keeper bot (`packages/keeper`): TypeScript + viem.

### 8. Test Infrastructure

- Dual-toolchain: Foundry (`forge test`) for core logic, Hardhat (`pnpm hardhat test`) for deployment and legacy helpers.

### 9. Repo structure: pnpm workspace monorepo

```
endure/
├── packages/
│   ├── contracts/          # Foundry/Hardhat; Venus fork + mocks
│   ├── sdk/                # TypeScript client
│   ├── frontend/           # Next.js frontend
│   ├── keeper/             # TypeScript liquidator bot
│   └── deploy/             # Deployment scripts
├── skills/                 # Domain knowledge for agents
├── docs/                   # Architecture, ADRs, briefs
└── scripts/                # Cross-package tooling
```

## Phased roadmap (Venus Rebase)

### Phase 0.5 — Venus Rebase

**Goal**: Transition the lending chassis from Moonwell v2 to Venus Protocol Core Pool.

**Scope**:
- Vendor Venus source tree byte-identical.
- Implement Venus-shape mocks (MockResilientOracle, AllowAllACM).
- Validate Diamond proxy routing and core lifecycle (Supply/Borrow/Repay/Redeem).
- Port test suites to Venus-based architecture.
- Update deployment scripts for Venus layout.

**Acceptance**:
- 100% test coverage on Venus chassis.
- Successful end-to-end lifecycle on local Anvil.
- Documentation reflects Venus-based architecture.
