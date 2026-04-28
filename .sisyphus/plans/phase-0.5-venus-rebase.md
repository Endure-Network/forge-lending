# Phase 0.5 Venus Rebase Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebase Endure's Phase 0 Moonwell lending core onto audited Venus Core Pool while preserving Endure's TAO-only, pooled-collateral behavior and local Anvil proof.

**Architecture:** Vendor Venus pinned commit `7c95843dc628535bfd0cf628c53bf7f7a2162932` into Foundry, wire Unitroller + Diamond + minimum facets, replace MToken markets with VBep20Immutable markets, and adapt Endure mocks/tests around Venus CF/LT semantics. Keep Stance B byte-identity discipline for upstream files and isolate all Endure-authored adapters/mocks.

**Tech Stack:** Solidity 0.8.25, Foundry, Venus Core Pool, pnpm workspace, Anvil, shell CI scripts.

---

## Chunk 1: Vendor and compile Venus minimum core

### Task 1: Add Venus upstream core files

**Files:**
- Modify: `packages/contracts/foundry.toml`
- Modify: `packages/contracts/remappings.txt`
- Create/replace: `packages/contracts/src/venus/**`
- Create: `packages/contracts/src/endure/venus/AllowAllAccessControlManager.sol`
- Create: `packages/contracts/src/endure/venus/MockResilientOracle.sol`
- Modify: `packages/contracts/UPSTREAM.md`
- Modify: `packages/contracts/FORK_MANIFEST.md`

- [ ] Write failing compile gate by importing Venus `VBep20Immutable`, `ComptrollerMock`, `ComptrollerLens`, and `TwoKinksInterestRateModel` in a temporary Foundry test.
- [ ] Run `forge test --root packages/contracts --match-contract VenusCompileSpikeTest -vvv`; expected: fail due missing vendored Venus files.
- [ ] Vendor only the minimum Venus Core Pool files and external interfaces needed for compilation.
- [ ] Update Foundry compiler to `0.8.25` and `evm_version = "cancun"`.
- [ ] Run the compile gate again; expected: pass.

### Task 2: Add Diamond selector verification test

**Files:**
- Create: `packages/contracts/test/endure/venus/VenusDiamondSelectors.t.sol`

- [ ] Write failing test `test_DiamondRegistersRequiredCoreSelectors` using Unitroller, Diamond, MarketFacet, SetterFacet, PolicyFacet.
- [ ] Run targeted test; expected: fail before deployment helper exists.
- [ ] Implement selector registration helper in test/deploy helper.
- [ ] Run targeted test; expected: pass.

---

## Chunk 2: Replace deployment helper

### Task 3: Rewrite `EndureDeployHelper` for Venus

**Files:**
- Modify: `packages/contracts/test/helper/EndureDeployHelper.sol`
- Modify: `packages/deploy/src/DeployLocal.s.sol`
- Modify: `packages/deploy/foundry.toml`

- [ ] Extract existing helper behavior assertions before deleting Moonwell deployment code.
- [ ] Write failing deploy test that requires vWTAO, vAlpha30, vAlpha64, comptroller proxy, diamond, lens, oracle, ACM, and IRMs to exist.
- [ ] Implement Venus deploy sequence exactly from the brief.
- [ ] Verify oracle prices are set before CF/LT.
- [ ] Verify borrow allowed only on vWTAO.
- [ ] Verify every market is seeded and burned.
- [ ] Run targeted deploy tests.

---

## Chunk 3: Restore behavior tests on Venus

### Task 4: Port lifecycle and liquidation tests

**Files:**
- Modify: `packages/contracts/test/endure/integration/AliceLifecycle.t.sol`
- Modify: `packages/contracts/test/endure/integration/Liquidation.t.sol`
- Create: `packages/contracts/test/endure/venus/LiquidationThreshold.t.sol`

- [ ] Write/port failing Alice lifecycle test against Venus addresses.
- [ ] Make it pass with Venus user-facing calls.
- [ ] Write/port failing liquidation test proving price-drop liquidation succeeds.
- [ ] Write failing test proving direct vToken liquidation works with `liquidatorContract == address(0)`.
- [ ] Write failing test proving LT and CF are separate: borrow uses CF; liquidation uses LT.
- [ ] Make all targeted integration tests pass.

### Task 5: Port seed, caps, RBAC, invariant tests

**Files:**
- Modify: `packages/contracts/test/endure/SeedDeposit.t.sol`
- Modify: `packages/contracts/test/endure/RBACSeparation.t.sol`
- Modify: `packages/contracts/test/endure/invariant/InvariantSolvency.t.sol`
- Modify: `packages/contracts/test/endure/invariant/handlers/EndureHandler.sol`

- [ ] Update seed tests for vTokens.
- [ ] Update cap tests for Venus cap semantics: borrow cap 0 means disabled.
- [ ] Replace Moonwell guardian tests with Venus ACM/admin tests appropriate to Phase 0.5.
- [ ] Update invariant handler addresses and user actions.
- [ ] Run invariant with configured 1000 runs and 50 depth.

---

## Chunk 4: CI, docs, and live-chain proof

### Task 6: Update CI and smoke test

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `scripts/e2e-smoke.sh`
- Modify: `scripts/check-stance-b.sh` or current Stance B audit script location
- Modify: `scripts/gas-snapshot-check.sh` only if test names change

- [ ] Update Stance B target from Moonwell to Venus pinned commit.
- [ ] Update smoke test addresses and event/error checks for Venus.
- [ ] Run Anvil deployment and smoke test locally.
- [ ] Run gas snapshot check with existing tolerance policy.

### Task 7: Update docs and architecture lock

**Files:**
- Modify: `README.md`
- Modify: `packages/contracts/README.md`
- Modify: `packages/contracts/UPSTREAM.md`
- Modify: `packages/contracts/FORK_MANIFEST.md`
- Modify: `skills/endure-architecture/SKILL.md`
- Create: `docs/briefs/phase-0.5-venus-rebase-brief.md`

- [ ] Replace Moonwell chassis language with Venus Core Pool language.
- [ ] Document the donation-attack-fixed Venus pin.
- [ ] Document Venus-specific footguns: CF/LT ordering, cap semantics, Diamond selectors, ComptrollerLens requirement.
- [ ] Document exact deviations from upstream Venus.

---

## Final verification

- [ ] Run `forge build --root packages/contracts`.
- [ ] Run `forge test --root packages/contracts`.
- [ ] Run `scripts/gas-snapshot-check.sh`.
- [ ] Run forbidden-pattern scan.
- [ ] Run Stance B audit.
- [ ] Run local Anvil deploy.
- [ ] Run `scripts/e2e-smoke.sh`.
- [ ] Run pnpm workspace test/build as CI requires.
