---
name: endure-architecture
description: "Use on every Endure Network task to ground decisions in locked architectural choices. Triggers on mentions of Endure, Endure Network, Endure Subnet, Endure Vault, lending protocol, vault, Phase 0-4 (any of them), monorepo layout, package structure, pooled collateral, TAO-only, Bittensor EVM lending, alpha collateral, MAlpha, MTao, EnduOracle, BittensorStakeAdapter, hotkey topology."
---

# Endure Network — Locked Architecture

This skill encodes the decisions that have been made. If a task seems to require re-litigating any of these, surface the conflict rather than silently deviating.

## What Endure is

A pooled-collateral, TAO-only lending protocol on Bittensor EVM. Users deposit alpha tokens (from Bittensor subnet AMMs) as collateral, borrow TAO against a combined account health factor. Forked from Moonwell v2 for the lending core; custody and oracle are Endure-new.

Separate from the **Endure Subnet** (SN30), which is a risk oracle subnet. The subnet feeds parameters into the lending protocol but is a distinct concern.

**One-line**: A pooled-collateral, TAO-only lending protocol on Bittensor EVM, forked from Moonwell v2 with Bittensor-native custody and oracle adapters, frontend derived from `aave/interface` over the Moonwell ABI.

## Locked decisions

### 1. Chassis: Moonwell v2 fork

- Repo: `moonwell-fi/moonwell-contracts-v2`
- License: BSD-3-Clause (permissive, no governance ask)
- Solidity: 0.8.19
- Build: Foundry
- Reason over alternatives: concentrated custody hooks in `doTransferIn/Out`, Compound V2 family battle-tested, supply/borrow caps built in, Foundry-first matches team workflow
- Rejected: Aave V3 (BUSL license blocker), Compound V3 (BUSL license blocker), Euler V2 (greenfield audit scope), Morpho Blue (isolated-markets-only, wrong model for pooled)

### 2. Borrow asset: TAO only

- Single base borrowable asset
- Alpha markets are collateral-only (borrow cap set to effectively zero)
- Simplifies oracle to TAO-denominated HF (no USD leg, no Chainlink TAO/USD)
- Simplifies liquidation to single alpha→TAO path
- Makes Aave V3's isolation/e-mode/silo features irrelevant (most of the feature advantages disappear)

### 3. Collateral model: pooled multi-collateral

- Users deposit basket of alpha across different netuids into one account
- Single HF computed across the basket
- No forced single-collateral posture (Aave's isolation mode not needed)
- Per-market collateral factors, supply caps, and borrow caps do the risk work

### 4. Custody: direct precompile via 0x805

- No ERC20 wrapper around alpha (TaoFi's AlphaToken ERC20 appears deprecated in favor of Hyperlane ICA)
- `MAlpha.sol` overrides `MErc20`'s `doTransferIn/Out` to call `BittensorStakeAdapter`
- Adapter wraps `0x805` with 9↔18 decimal conversion and tempo-lock handling
- Consult `bittensor-precompiles` skill for mechanics

### 5. Hotkey topology: single hotkey at MVP

- All alpha deposits route through one Endure hotkey per netuid
- `StakingOperationRateLimiter` is 1 op/block per `(hotkey, coldkey, netuid)` — 12s serialization is fine at MVP volumes
- Multi-hotkey sharding reserved for Phase 3+ if contention emerges

### 6. Off-chain language: TypeScript everywhere

- SDK (`packages/sdk`): wraps `@moonwell-fi/moonwell-sdk` + Endure extensions
- Frontend (`packages/frontend`): Next.js
- Keeper bot (`packages/keeper`): TypeScript + viem, not Python
- Rationale: unified type generation from contract ABIs via wagmi CLI; single-language off-chain stack
- Exception: Python remains fine for unrelated concerns (e.g. SN30 risk oracle backend), but that's separate from this protocol

### 7. Frontend: two-phase — minimal dashboard early, aave/interface fork later

- **Phase 1**: minimal dashboard — shadcn/ui + wagmi + `@moonwell-fi/moonwell-sdk`, no branding, no polish. Purpose: human-operable testnet validation, early product feedback, SDK-gap discovery.
- **Phase 4**: production frontend — fork `aave/interface` (BSD-3 licensed), port validated flows from Phase 1's minimal dashboard, strip multi-borrow UX, add Bittensor affordances. Purpose: launch-quality UX.
- Rationale for two phases: doing production UI as the first frontend work conflates ABI translation, SDK-gap discovery, UX decisions, and polish work — all at the same moment, three weeks from audit. Splitting them lets each phase solve one problem well.
- Consult `frontend-stack` skill for stack details and the minimal-vs-production split.

### 8. On-chain tooling: Foundry

- `forge test`, `forge script`, `forge coverage`, `forge snapshot`
- Invariant testing is first-class
- Matches Moonwell v2 upstream

### 9. Repo structure: pnpm workspace monorepo

```
endure/
├── packages/
│   ├── contracts/          # Foundry; Moonwell fork + BittensorStakeAdapter + MAlpha + EnduOracle
│   ├── sdk/                # TypeScript client; wraps moonwell-sdk + Endure-specific extensions
│   ├── frontend/           # Next.js; fork of aave/interface with Moonwell ABI layer
│   ├── keeper/             # TypeScript liquidator bot; health factor monitoring + liquidateBorrow
│   └── deploy/             # Foundry scripts; mip-style proposal scaffolding
├── skills/                 # Prometheus skills (domain knowledge for the coding agent)
├── docs/                   # Architecture, ADRs, briefs, risk dossiers
├── prompts/                # Prometheus briefs per phase
└── scripts/                # Cross-package tooling (ABI generation, type generation)
```

- Audit freeze via git tag (`contracts-v1.0-audit`), not separate repo
- If/when Endure scales, split `contracts/` into its own repo — one-command operation

### 10. Interest rate model: JumpRateModelV2

- JumpRateModel (Moonwell default) on TAO market; alpha markets set borrow cap to effectively zero
- TAO-only borrow means only TAO market needs an IRM tuned
- Base rate 2%/year, multiplier 10%/year (to kink), jump multiplier 300%/year (above kink), kink 80% utilization
- Upstream contract name is `JumpRateModel.sol` — the "V2" in older Endure docs refers to the Moonwell default; do not grep for `JumpRateModelV2.sol` as a filename

## Phased roadmap

### Phase 0 — Local Anvil, mock ERC20 collateral (Days 1-7)

**Goal**: validate the Moonwell fork is clean and deployable with zero Bittensor dependency.

**Scope**:
- Initialize pnpm workspace monorepo
- Fork `moonwell-fi/moonwell-contracts-v2` into `packages/contracts`
- Strip cross-chain governance (`TemporalGovernor`, `MultichainGovernor`, `MultichainVoteCollection`, `WormholeBridgeBase`, `StakedWell`, `xWELL`)
- Replace with deployer EOA as admin (Timelock + GovernorBravo deferred to Phase 4)
- Pin Solidity to 0.8.19
- Write `MockAlpha` ERC20s (one per tracked netuid: 30, 64 for MVP)
- Deploy script for local Anvil: TAO market (native wrap mock) + two mock alpha markets
- End-to-end Foundry test: supply → borrow → repay → close; supply → price drop → liquidate
- Initial gas benchmarks

**Acceptance**:
- `forge test` all green on stripped base
- `forge script Deploy --rpc-url http://localhost:8545 --broadcast` runs clean
- End-to-end integration test demonstrates supply/borrow/repay/close cycle
- End-to-end integration test demonstrates liquidation after oracle price move
- Invariant test: total borrowed ≤ total supplied + reserves
- README in `packages/contracts` documents the delta from upstream Moonwell

**Out of scope**: any Bittensor-specific code, any precompile references, any real oracle beyond a trivial mock, any frontend work.

### Phase 1 — Bittensor testnet contracts + minimal dashboard (Days 7-17)

**Goal**: validate Moonwell fork runs on Subtensor EVM, and get a human-operable interface against real testnet state. Unblocks all subsequent product feedback.

**Contract scope**:
- Add Bittensor testnet (chain 945) config to `foundry.toml`
- Deployment script funds deployer H160 via btcli wallet transfer flow (documented, not automated)
- Deploy full stack to chain 945 with mock ERC20 collaterals
- Verify contracts on Bittensor block explorer
- Smoke test: supply/borrow/repay/liquidate on chain 945
- Gas cost comparison vs local Anvil
- Document any RPC quirks or Frontier-specific behavior

**SDK scope** (`packages/sdk`):
- Initialize as TypeScript workspace package
- Wrap `@moonwell-fi/moonwell-sdk` and add Endure-specific extensions
- Type generation from Endure contract ABIs via wagmi CLI
- Client factory: `createEndureClient({ chainId, rpcUrl })`
- Action helpers: `getMarkets`, `getUserPosition`, `supply`, `borrow`, `repay`, `close`, `liquidate`
- Subtensor EVM chain config (chain 945 for testnet, 964 for Finney) as exported constant

**Frontend scope** (`packages/frontend`) — minimal dashboard, NOT the production UI:
- Next.js App Router + TypeScript + Tailwind + shadcn/ui + wagmi v2 + viem + RainbowKit
- Brutalist layout, shadcn defaults — no custom branding, no polish, no marketing pages
- 4-6 screens, functional:
  - Connect wallet (RainbowKit + Subtensor EVM chain config)
  - Markets table (name, supply APY, borrow APY, caps, your balance)
  - Supply/Redeem form (per-market)
  - Borrow/Repay form (TAO market)
  - Positions view (collateral, debt, HF)
  - Liquidations view (read-only list of liquidatable accounts)
- Uses `packages/sdk` for all contract interactions — no direct wagmi calls in components
- Deployed to a preview URL (Vercel / IPFS / whatever is simplest)

**Acceptance**:
- Contracts verified on Subtensor EVM testnet
- Integration test fork-mode run against chain 945 passes
- Gas cost report in `docs/gas-benchmarks.md`
- Dashboard renders live markets from testnet, wallet connect works, full supply/borrow/repay/close flow executable end-to-end by a human (not just tests)
- SDK unit tests cover all exported actions

**Out of scope**: precompile integration, real alpha, oracle beyond mock, aave/interface fork, brand/polish, responsive design, SEO, mobile, analytics. The minimal dashboard is for internal testing and partner demos, not public launch.

### Phase 2 — Bittensor staking adapter, mocked precompile (Days 17-25)

**Goal**: write and test the `BittensorStakeAdapter` in isolation before touching a real subtensor node.

**Scope**:
- `IStakingV2.sol` interface matching the 0x805 ABI
- `BittensorStakeAdapter.sol` — wraps precompile calls with 9↔18 decimal conversion, tempo-lock state tracking, slippage-aware quote functions
- Mock `IStakingV2` contract deployable to Anvil for local testing
- Differential fuzz tests comparing adapter behavior against mock
- `MAlpha.sol` — override of `MErc20` using adapter in `doTransferIn/Out`
- Unit tests for all adapter paths
- Invariant tests: adapter-owned alpha accounting matches underlying stake

**Acceptance**:
- `forge test --match-contract BittensorStakeAdapter` all green
- Fuzz tests pass at ≥10M runs per property
- `MAlpha` supports full `MToken` lifecycle with adapter backing
- Documentation of tempo-lock timing assumptions and their implications

**Out of scope**: real subtensor node integration, oracle, frontend.

### Phase 3 — Real alpha on Bittensor testnet (Days 25-35)

**Goal**: first end-to-end on real Bittensor semantics.

**Scope**:
- Replace mock alpha ERC20s with `MAlpha` markets backed by real precompile
- `EnduOracle.sol` implementing Moonwell's `PriceOracle` interface; reads subnet AMM reserves via MetagraphPrecompile for TAO-denominated alpha pricing
- Sanity checks: staleness bound, deviation guard, circuit breaker, admin-pause
- Integration tests against Bittensor testnet's real `0x805`
- Deployment script updated for testnet alpha markets
- Minimal dashboard evolves: add netuid selector, hotkey display, tempo-lock countdown, oracle price source tooltip. Incremental changes to existing screens, not a rewrite.
- SDK adds Bittensor-specific helpers: `getAlphaPrice(netuid)`, `getTempoLockStatus(user, netuid)`, `getSubnetReserves(netuid)`

**Acceptance**:
- User can supply testnet alpha from an H160-mirrored SS58, borrow testnet TAO, repay, close
- Liquidation executes cleanly with oracle-driven price movement
- Oracle circuit breaker trips on >25% single-block deviation and halts new borrows
- All Phase 2 invariants still pass on testnet

**Out of scope**: mainnet deploy, audit, production keeper bot.

### Phase 4 — Hardening, production frontend, audit prep (Days 35-56)

**Goal**: ship-ready hardening, production-quality frontend, audit-ready documentation.

**Scope**:
- Empty-market first-deposit donation fix: admin seed deposit + `MINIMUM_LIQUIDITY` burned shares + round-in-protocol-favor in `exchangeRateStoredInternal` and `redeemFresh` (see `docs/moonwell-risks/empty-market-donation.md`)
- Tempo-lock guard revert reasons — make them liquidator-retryable
- Multi-source oracle: subnet AMM primary, 30-min TWAP secondary, admin-override last-resort
- Keeper bot (`packages/keeper`): health factor monitoring via `getAccountLiquidity`, liquidation execution with bounty optimization, MEV-resistance patterns
- **Production frontend upgrade**: fork `aave/interface` (BSD-3), port flows and SDK integration learned from the Phase 1-3 minimal dashboard, strip multi-borrow UX (market picker for borrow asset, stable/variable rate toggle, e-mode selector), add Bittensor affordances already validated in the minimal dashboard, apply brand/polish/responsive/accessibility. Minimal dashboard can be retired or kept as an internal tool.
- Invariant test suite: no path from `doTransferIn` to `mint` that bypasses tempo lock; HF monotonicity; exchange rate monotonicity except via reserves
- Property-based fuzz on decimal conversion edges
- Documentation: deployment runbook, liquidator integrator guide, oracle threat model
- Audit RFP — scoped to new Bittensor-specific code only (~2,000 LOC)

**Acceptance**:
- Audit RFP sent to at least three firms (OpenZeppelin, Trail of Bits, ChainSecurity suggested)
- Frontend deployed to testnet with full user flow
- Keeper bot liquidates successfully on testnet under adversarial scenarios
- All invariant tests pass at production thresholds

**Out of scope**: audit remediation (post-audit work), mainnet deploy (post-audit), mainnet keeper infrastructure.

## Non-goals across all phases

- Cross-chain deployments (Finney only)
- Flash loans
- Isolation mode, e-mode, siloed markets
- Governance token (may come later; not MVP)
- Wormhole / cross-chain messaging
- Alpha-to-alpha swaps via `swapStake` (doesn't exist on precompile)
- Mobile app
- Leverage-looping UX

## Dependencies that affect timelines

| Dependency | Status (April 2026) | Impact |
|---|---|---|
| PR #2478 (`approve`/`transferStakeFrom`) | Merged to `devnet-ready`, not Finney | Blocks atomic deposit on mainnet. Phase 3 testnet work fine with pre-#2478 two-step fallback; Phase 4 mainnet deploy gated on promotion. |
| Issue #2573 (subnet dereg allowance cleanup) | Open | Affects long-lived allowance handling. Monitor resolution. |
| Issue #2455 (precompile versioning) | Open RFC | Affects ABI stability planning. Use typed interface wrappers, not hardcoded addresses. |
| `aave/interface` license | Confirmed BSD-3 | Frontend fork is license-clean. |
| `@moonwell-fi/moonwell-sdk` | MIT, actively maintained | SDK backbone for off-chain stack. |

## Risk register

| # | Risk | Mitigation |
|---|---|---|
| 1 | Empty-market donation attack (Sonne/Hundred/Venus-THE class) | Admin seed deposit + burned `MINIMUM_LIQUIDITY` + round-in-protocol-favor (Phase 4). Phase 0 ships seed+burn as the first leg. See `docs/moonwell-risks/empty-market-donation.md`. |
| 2 | Tempo-lock preventing liquidation in narrow windows | Liquidator retryable revert + HF buffer in liquidation threshold |
| 3 | Alpha price manipulation via subnet AMM | Multi-source oracle + deviation guard + circuit breaker + conservative initial LTV (20-25%) |
| 4 | Chain halt during liquidation queue | Oracle staleness degradation; interest accrual bounded by admin-adjustable cap during halts |
| 5 | Precompile ABI drift (issue #2455) | Typed Solidity interfaces, selector-upgrade playbook, avoid `StorageQueryPrecompile` |
| 6 | 9↔18 decimal conversion bugs | Property-based fuzz tests; single conversion utility in adapter |
| 7 | Single-hotkey rate limit contention at scale | Multi-hotkey sharding reserved for Phase 3; monitor rate-limit errors in keeper |
| 8 | Bad debt from under-collateralized liquidations | Conservative initial LTV (20-25% tier-1), insurance fund from interest revenue |

## When architecture questions arise

- **New precompile or Bittensor-specific question**: consult `bittensor-precompiles` skill first
- **Moonwell-specific risk (empty-market attack, deployment footguns)**: consult `docs/moonwell-risks/` dossiers
- **Deployment or RPC question**: consult `bittensor-evm-deployment` skill
- **SDK, frontend, keeper, or TypeScript off-chain work**: consult `frontend-stack` skill
- **Fundamental architecture question not answered by skills**: flag to the human maintainer; don't silently deviate

## Related skills and references

| Resource | When to consult |
|---|---|
| `bittensor-precompiles` | Every Solidity task touching 0x805, H160↔SS58, decimal conversion, tempo locks |
| `bittensor-evm-deployment` | Deployment, RPC config, gas funding, contract verification |
| `docs/moonwell-risks/empty-market-donation.md` | Phase 4 empty-market fix design and rationale |
| `docs/moonwell-risks/deployment-footguns.md` | Market listing sequence, cap semantics, upgrade posture |
| `frontend-stack` | Any SDK, frontend, keeper, or TypeScript off-chain work |
| `endure-architecture` (this file) | Grounding any task in the locked decisions above |
