# Endure Network — Phase 0: Moonwell Fork + Local Anvil Deploy

> **Historical provenance**: this is the original Phase 0 task brief as authored
> at project kickoff. Preserved verbatim for audit/review purposes. Phase 0
> shipped against this scope; see `packages/contracts/README.md` and
> `packages/contracts/FORK_MANIFEST.md` for what was actually built.

## Project context

Endure Network is a pooled-collateral, TAO-only lending protocol for Bittensor EVM (chain ID 964 mainnet, 945 testnet). Users will deposit alpha tokens (from Bittensor subnet AMMs) as collateral and borrow TAO against a combined account health factor.

The protocol is a fork of Moonwell v2 (Compound V2 lineage, BSD-3 licensed), with Bittensor-specific custody and oracle adapters added later. Off-chain stack is TypeScript (SDK, frontend, keeper bot). On-chain tooling is Foundry.

This is a pnpm workspace monorepo, fresh. Nothing exists yet.

Architectural decisions are locked in `skills/endure-architecture/SKILL.md` (read it before planning).

## This task — Phase 0

The goal is to stand up the project skeleton and prove the Moonwell fork deploys cleanly to local Anvil with mock ERC20 collaterals, before any Bittensor-specific code is written.

**In scope**:
- Initialize the pnpm workspace monorepo at the repo root
- Create `packages/contracts/`, `packages/sdk/`, `packages/frontend/`, `packages/keeper/`, `packages/deploy/` as workspace packages (frontend/keeper/sdk can be minimal stubs in Phase 0 — just enough for the workspace to resolve)
- In `packages/contracts/`, fork `moonwell-fi/moonwell-contracts-v2` (clone at a specific commit and strip the `.git/` folder so it becomes Endure-owned code). Document the upstream commit in `packages/contracts/UPSTREAM.md`.
- Strip the cross-chain governance surface: `TemporalGovernor`, `MultichainGovernor`, `MultichainVoteCollection`, `WormholeBridgeBase`, `StakedWell`, `xWELL`. Remove Wormhole dependencies from `foundry.toml` and remappings.
- Replace stripped governance with a minimal setup: standard Compound `Timelock` and either `GovernorBravoDelegate` or (simpler for MVP) an immutable admin multisig address with pause-only authority.
- Strip multi-reward distributor; Endure won't have multi-token emissions at MVP.
- Pin Solidity to 0.8.19, `evm_version = "shanghai"` in `foundry.toml`.
- Get `forge test` green on the stripped base (all remaining tests pass, or are deleted if they test stripped functionality).
- Write two `MockAlpha` ERC20 contracts: `MockAlpha30` and `MockAlpha64` (representing future netuid 30 and 64 alpha tokens). Simple OpenZeppelin-based ERC20s with mint/burn for testing.
- Write an `MTao` market variant or use Moonwell's existing native-token variant (whichever is simpler) for the TAO borrowable market, using a mock WTAO (wrapped TAO) ERC20 for Phase 0 since there's no native TAO on local Anvil.
- Write a Foundry deploy script (`packages/deploy/src/DeployLocal.s.sol`) that does the full stack atomically:
  1. Deploys Comptroller (Unitroller + Delegate)
  2. Deploys `JumpRateModelV2` instances
  3. Deploys mock oracle returning fixed prices for each asset
  4. Deploys WTAO mock, MockAlpha30, MockAlpha64
  5. Deploys the MToken markets: `mWTAO`, `mMockAlpha30`, `mMockAlpha64`
  6. Supports each market in Comptroller
  7. Sets collateral factors: 0 for `mWTAO` (not usable as collateral at MVP), 0.25e18 for both alpha markets
  8. Sets supply caps: 10,000 units per alpha market, unlimited WTAO
  9. Sets borrow caps: `mWTAO` unlimited (borrowable), alpha markets set to 1 wei (effectively disabled)
  10. Sets close factor 0.5e18, liquidation incentive 1.08e18
  11. Admin seed deposit: mints a small amount of each market to `0xdEaD` to prevent empty-market donation attacks (see Domain knowledge below for pattern)
- Write an end-to-end Foundry integration test that demonstrates a full user flow:
  - Alice supplies 100 MockAlpha30 as collateral
  - Alice borrows 10 WTAO against it
  - Time passes, interest accrues
  - Alice repays the borrow + interest
  - Alice closes her position, gets her collateral back
- Write a second integration test for liquidation:
  - Alice supplies alpha, borrows
  - Mock oracle drops alpha price
  - Alice's HF < 1
  - Bob calls `liquidateBorrow` and seizes Alice's collateral at a discount
- Write one invariant test: total borrowed WTAO across all borrowers ≤ total supplied WTAO + reserves at all times
- Write a `README.md` in `packages/contracts/` documenting the delta from upstream Moonwell
- Gas snapshot of the major flows (`forge snapshot` output committed)

**Out of scope — do NOT do these in Phase 0**:
- Any Bittensor-specific code (precompile interfaces, H160↔SS58 math, adapter contracts)
- Any reference to `0x805`, `IStakingV2`, `BittensorStakeAdapter`, `MAlpha`, `EnduOracle`
- Deployment to Bittensor EVM testnet — local Anvil only
- Oracle beyond a trivial `MockPriceOracle` returning constants set by admin
- Frontend UI beyond a stub `packages/frontend/README.md`
- Keeper bot logic beyond a stub `packages/keeper/README.md`
- SDK beyond a stub `packages/sdk/README.md`
- Empty-market donation fix (deferred to Phase 4) — but DO include the admin seed deposit as described, because it's a prerequisite and cheap to add now
- Governor Bravo full setup with voting — immutable admin multisig is fine for MVP
- Real WTAO wrapper (using a mock ERC20 in Phase 0)

## Domain knowledge

### Moonwell v2 fork structure (detailed reference: `docs/moonwell-risks/`)

Moonwell is a Compound V2 descendant. The architecture has three layers:

1. **Risk engine**: `Comptroller.sol` (via `Unitroller` proxy) holds per-market risk parameters and the health factor check. A user's HF = Σ(collateral_value_i × CF_i) / Σ(borrowed_value_i).

2. **Per-market contracts**: each asset has an `MErc20Delegator` (proxy) + `MErc20Delegate` (logic) pair. The delegate inherits from `MErc20` which inherits from `MToken`. `MToken` has the core `mint`, `redeem`, `borrow`, `repayBorrow`, `liquidateBorrow` logic. `MErc20` implements the custody hooks `doTransferIn` and `doTransferOut` using `IERC20.safeTransferFrom/safeTransfer`.

3. **Rate and oracle**: each market has its own `JumpRateModelV2` instance. A single `PriceOracle` (implementation: `ChainlinkOracle` upstream) serves the whole Comptroller.

The custody hooks in `MErc20` are where Endure's Bittensor adapter will plug in later. In Phase 0, the stock `MErc20` with a real ERC20 mock is fine.

### What to strip and why

Moonwell's upstream has a lot of cross-chain governance scaffolding (Wormhole-based) that Endure doesn't need. Strip:
- `TemporalGovernor.sol` — Wormhole-relayed governance to non-Moonbeam chains
- `MultichainGovernor.sol` — Moonbeam-based governance hub
- `MultichainVoteCollection.sol` — Vote aggregation across chains
- `WormholeBridgeBase.sol` — Wormhole primitives
- `StakedWell` (stkWell) — WELL token staking, unrelated to lending
- `xWELL` — cross-chain WELL token
- `MultiRewardDistributor.sol` — multi-token emissions (not needed for MVP)
- All tests that exercise the above

**Do NOT strip**:
- `Comptroller`, `Unitroller`, `MToken`, `MErc20`, `MErc20Delegator`, `MErc20Delegate`, `JumpRateModelV2`
- `ChainlinkOracle` and `ChainlinkCompositeOracle` (they'll be replaced by `EnduOracle` later, but keep them as reference for Phase 0)
- Test utilities in `test/` that are useful base classes (inspect and keep what's reusable)

### The Unitroller + Delegator proxy pattern

Moonwell uses two separate proxy patterns side by side:
- `Unitroller` holds Comptroller state and delegates to `Comptroller` implementation. Upgrade via `_setPendingImplementation` + `_acceptImplementation`.
- `MErc20Delegator` holds per-market state and delegates to `MErc20Delegate` implementation. Upgrade via `_setImplementation`.

Phase 0 deploy script should use both patterns as-is; do not refactor.

### Supply cap, borrow cap, collateral factor semantics

- `collateralFactorMantissa`: 18-decimal fixed-point percentage. 0.25e18 = 25%. Setting to 0 disables use as collateral.
- `supplyCap`: absolute cap in underlying units. 0 = unlimited.
- **`borrowCap`: 0 means UNLIMITED, not disabled.** To disable borrowing on an alpha market, set to 1 wei or use the pause guardian. This is a common mistake — flag it in the plan.
- `closeFactorMantissa`: fraction of outstanding debt a liquidator can repay in one call. 0.5e18 = 50%.
- `liquidationIncentiveMantissa`: multiplier on seized collateral. 1.08e18 = 8% bonus.
- `reserveFactorMantissa`: fraction of borrow interest that goes to reserves. 0.15e18 = 15%.

### Admin seed deposit pattern (do this in Phase 0)

To prevent the empty-market first-deposit donation attack (Sonne lost $20M to this on May 14, 2024), every market should be seeded at listing time:

1. Admin mints a small amount of underlying (e.g. 1 unit)
2. Admin approves the MToken for that amount
3. Admin calls `MToken.mint(seedAmount)`
4. The resulting mTokens are transferred to `address(0xdEaD)`, permanently locking them

This establishes `totalSupply > 0` on every market from the moment it's live. Subsequent direct donations of underlying dilute across existing shares instead of enabling the rate-manipulation attack.

This is a simple pattern (5-10 lines per market in the deploy script) and should be in Phase 0. The deeper fix (round-in-protocol-favor in `exchangeRateStoredInternal`) is deferred to Phase 4.

### Atomic market listing

A new market must be fully configured in a single transaction (or a single timelock execution). The order matters:

1. Deploy `MErc20Delegator` with `MErc20Delegate` as implementation
2. Deploy `JumpRateModelV2` with curve parameters
3. Call `Comptroller._supportMarket(mToken)` — MUST come before any user interaction
4. Call `Comptroller._setCollateralFactor(mToken, cf)`
5. Call `Comptroller._setMarketSupplyCaps([mToken], [cap])`
6. Call `Comptroller._setMarketBorrowCaps([mToken], [cap])`
7. Call `mToken._setReserveFactor(rf)`
8. Call `mToken._setInterestRateModel(irm)` if not set in constructor
9. Admin seed deposit + burn

Moonwell's `mip-b00.sol` is the canonical template for this. Reference it; do not reinvent the sequence.

### Common pitfalls for the plan to flag

- Forgetting to call `_supportMarket` before trying to set parameters on a market → reverts with unhelpful error
- Setting `borrowCap = 0` on alpha markets thinking it disables borrow → actually enables unlimited (existential bug in production)
- Missing the admin seed deposit → market is listed empty, vulnerable to donation attack (even if not exploited in Phase 0, establishes bad muscle memory)
- Trying to run `forge build` before stripping Wormhole dependencies → compile errors
- Importing from `@moonwell/...` paths after the fork → phantom dependencies, reconfigure remappings

## What exists today

Nothing. This is a fresh repo.

- No prior commits to Endure
- No prior Prometheus plans
- The user has four skill files in `skills/` that encode domain knowledge — consult `endure-architecture/SKILL.md`, `moonwell-fork-patterns` references during planning
- `docs/architecture.md` has the full phased roadmap — reference it to confirm Phase 0 scope boundaries

## Success criteria

Phase 0 is done when ALL of the following are true:

1. **Monorepo initialized**: `pnpm install` at repo root succeeds; workspace packages resolve.
2. **Moonwell fork stripped clean**: `forge build` in `packages/contracts/` succeeds with no warnings about missing imports or unreferenced files. Wormhole is gone from dependencies.
3. **Test suite green**: `forge test` in `packages/contracts/` passes 100% of remaining tests.
4. **Local deploy works**: `anvil` running + `forge script packages/deploy/src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast` runs to completion without reverts. Script outputs deployed addresses to a JSON artifact.
5. **End-to-end supply/borrow test passes**: integration test demonstrates Alice supply→borrow→repay→close cycle.
6. **Liquidation test passes**: integration test demonstrates oracle-driven liquidation.
7. **Invariant test passes**: `forge test --match-test invariant_TotalBorrowLeqTotalSupply` passes with default Foundry invariant runs (>= 1000).
8. **Admin seed present**: every market has `totalSupply > 0` after deploy, with seed mTokens locked at `0xdEaD`. Verified by test.
9. **Gas snapshot committed**: `packages/contracts/.gas-snapshot` present and reflects current implementations.
10. **Documentation**: `packages/contracts/README.md` documents the deltas from upstream Moonwell; `packages/contracts/UPSTREAM.md` documents the upstream commit hash the fork is based on.

Explicitly not required for Phase 0 completion: any Bittensor integration, frontend work, keeper bot logic, deployment to any chain other than local Anvil, full governance setup.

---

*After Phase 0 lands, Phase 1 will deploy the same contracts (still mock ERC20 collaterals) to Bittensor EVM testnet (chain 945) to validate Subtensor EVM compatibility. Phase 2 will write the `BittensorStakeAdapter` against a mocked precompile. Each phase gets its own Prometheus brief.*
