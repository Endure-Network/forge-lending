# Phase 0.5 Venus Rebase — Implementation Plan

> **For agentic workers**: REQUIRED — Use `superpowers:subagent-driven-development` (if subagents available) or `superpowers:executing-plans` to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking. **Source spec**: `docs/briefs/phase-0.5-venus-rebase-spec.md` (792 lines, treat as source of truth — every locked decision and Stage A finding F1–F10 in that spec is binding).

## TL;DR

> **Quick Summary**: Rebase Endure's Phase 0 Moonwell v2 lending core onto a vendored Venus Protocol Core Pool fork (commit `6400a067114a101bd3bebfca2a4bd06480e84831` / tag `v10.2.0-dev.5`) so Endure inherits Venus's audited separate `collateralFactorMantissa` and `liquidationThresholdMantissa` semantics. Stage A is already GREEN (Venus tree vendored at `src/venus-staging/`, 7 spike tests passing, Phase 0 Moonwell tests still green under dual-vendor Foundry config). This plan covers Stage B Chunks 1–6.
>
> **Deliverables**:
> - Hardhat toolchain side-by-side with Foundry, dual solc 0.8.25 + 0.5.16 (Chunk 1)
> - Rewritten `EndureDeployHelper.sol` deploying the Venus chassis (Unitroller + Diamond + 4 facets + ComptrollerLens + ACM + ResilientOracle + VBep20Immutable markets) (Chunk 2)
> - All Phase 0 Foundry tests ported to Venus + 4 net-new Venus-semantic tests + behavior-mapping table CI gate (Chunk 3)
> - All 37 non-fork Venus Hardhat tests green with VAI/Prime/XVS/VRT/Liquidator/Swap/DelegateBorrowers fixture infrastructure (Chunk 4)
> - CI repointed (Stance B audit at Venus pin, e2e-smoke for Venus, gas-snapshot rebaselined, forbidden-pattern scan for Moonwell remnants), `scripts/e2e-smoke.sh` Venus-rewritten (Chunk 5a)
> - Mass-move (`git mv src/venus-staging/* src/`) + delete-Moonwell as THREE atomic commits per Metis split: A (delete Moonwell, CI red), B1 (mass-move + path/audit/Hardhat updates, Foundry may stay red), B2 (dual-helper teardown, Foundry GREEN restored) (Chunk 5b)
> - Documentation rewrite: README, UPSTREAM, FORK_MANIFEST, `skills/endure-architecture/SKILL.md` (Chunk 6)
> - Final: squash-merge `phase-0.5-venus-rebase` to `main`, with TWO archival tags: `phase-0-moonwell-final` (pinned at planning-time `main` SHA `de5238ef41f38fa11db000ee899f0f102c5f19e5` — see Final Integration entry in Commit Strategy for handling unrelated `main` activity during execution) AND `v0.5.0-venus` (on the squash-merge commit, marking Venus genesis)
>
> **Estimated Effort**: XL (multi-week, 55 implementation tasks (T1–T51 + T22b + T25b + T25c + T46b) + 4 final-wave reviewers, dual-toolchain, byte-identity audit gating)
> **Parallel Execution**: YES — 7 implementation waves + 1 final review wave (~20 parallel tasks at peak in Wave 4)
> **Critical Path**: T1 → T6 (Hardhat compile gate) → T11 (deploy helper green) → T15 (Foundry port green) → T31 (Hardhat port green) → T39 (e2e-smoke green) → T43 (mass-move green) → F1–F4 → user okay → squash-merge

---

## Context

### Original Request

User asked to "review `docs/briefs/phase-0.5-venus-rebase-spec.md` and help me build a plan." The spec is a 792-line authoritative document that supersedes the previous draft and the older `phase-0.5-venus-rebase-brief.md`. Stage A (Task 0) is already complete on branch `phase-0.5-venus-rebase` (commit 90e8c80).

### Path Conventions (CRITICAL — read before executing)

**The plan uses two path conventions. An executor MUST resolve them as follows.**

1. **Repo-root paths** (start with `packages/`, `scripts/`, `docs/`, `.github/`, `.sisyphus/`, `README.md`, `skills/`): used as-is from the workspace root (`/Users/ignacioblitzer/Develop/endure/forge-lending/`). Examples: `packages/contracts/foundry.toml`, `scripts/e2e-smoke.sh`, `.github/workflows/ci.yml`, `docs/briefs/phase-0.5-venus-rebase-spec.md`.

2. **Contract-package-relative paths** (bare `src/`, `test/`, `lib/`, `tests/hardhat/`, `script/`, `deploy/`, `foundry.toml`, `remappings.txt`, `hardhat.config.ts`, `tsconfig.json`, `package.json`, `FORK_MANIFEST.md`, `UPSTREAM.md`, `.upstream-sha`, `.gas-snapshot`): MUST be interpreted as relative to `packages/contracts/`. Example: `src/venus-staging/Comptroller/Diamond/Diamond.sol` IS `packages/contracts/src/venus-staging/Comptroller/Diamond/Diamond.sol`. `test/endure/venus/Lifecycle.t.sol` IS `packages/contracts/test/endure/venus/Lifecycle.t.sol`. `foundry.toml` IS `packages/contracts/foundry.toml`.

3. **Special exception**: `packages/deploy/src/DeployLocal.s.sol` is the deploy-script package's own `src/` — referenced as a full path `packages/deploy/src/...` in every occurrence to avoid confusion.

**Why two conventions?** Solidity work happens almost entirely under `packages/contracts/`, so bare `src/`, `test/`, `lib/` reads naturally. Repo-root paths are reserved for everything outside the contracts package. When in doubt, prefer the explicit `packages/contracts/...` form. F4 (Scope Fidelity Check) MUST normalize both forms when matching task scopes against actual diffs.

**Verifying any bare path during execution**: Run `ls packages/contracts/<bare-path>` from the workspace root.

### Documented Deviations from Spec

The spec is the source of truth EXCEPT for the following points, all approved by the user during the planning interview:

- **Tag strategy** (spec lines 711, 738, 787 superseded): Spec specifies a single archival tag `moonwell-v0.1.0`. Plan uses TWO tags: `phase-0-moonwell-final` on the pre-merge `main` commit (archives the last Moonwell commit) and `v0.5.0-venus` on the post-merge squash commit (marks Venus genesis). Rationale: clearer history, both endpoints labeled.
- **RewardFacet scope + selector cut + isolation carve-out** (spec line 771 superseded; spike facet cut amended): Spec says "No production rewards (RewardFacet deployed with zero state purely to satisfy PolicyFacet inheritance)." Plan elevates this to "RewardFacet is FULLY FUNCTIONAL and opt-in." Rewards stay zero by default; admin can activate them via `enableVenusRewards(xvs, vTokens, supplySpeeds, borrowSpeeds)` exposed by the helper.
  - **Surface expansion**: Endure-authored `src/endure/MockXVS.sol` (~30 LOC, simple OZ ERC20 for testing the reward enable path) AND `test/endure/venus/RewardFacetEnable.t.sol` (T22b's usability test).
  - **Selector cut expansion**: Spike's `_rewardFacetSelectors()` only registers 2 of 7 RewardFacet selectors. T8's expected count + T9's actual cut expand the diamond cut as follows:
    - **MarketFacet** (+2 storage-getter selectors vs spike): add `venusSupplySpeeds(address)` + `venusBorrowSpeeds(address)` — auto-generated from `ComptrollerStorage.sol:234` and `:231` (`public` mappings). Required so T22b Tests 1+2 can read per-market XVS speeds via the diamond. Convention from finding F1: ComptrollerStorage public state-variable getters register on MarketFacet.
    - **PolicyFacet** (+1 selector vs spike): add `_setVenusSpeeds(VToken[],uint256[],uint256[])` — verified at `src/venus-staging/Comptroller/Diamond/facets/PolicyFacet.sol:477` (NOT SetterFacet, contrary to earlier draft).
    - **SetterFacet** (+1 selector vs spike): add `_setXVSToken(address)` — verified at `SetterFacet.sol:604`. Required so T22b's `enableVenusRewards(...)` can register the mock XVS via the diamond.
    - **RewardFacet** (+6 selectors vs spike): expand from spike's 2 (`claimVenus(address)` + `getXVSVTokenAddress`) to 8 selectors: add `claimVenus(address,VToken[])`, `claimVenus(address[],VToken[],bool,bool)`, `claimVenusAsCollateral(address)`, `_grantXVS(address,uint256)`, `seizeVenus(address[],address)`, and `getXVSAddress()` (from FacetBase at `FacetBase.sol:234`, registered on RewardFacet by convention).
    - **Total selector cut**: spike 61 → 71 (+10: 2 MarketFacet + 1 PolicyFacet + 1 SetterFacet + 6 RewardFacet).
  - **Isolation carve-out**: T30/T31/T32/T33 isolation greps that previously asserted "no XVS in Endure surface" now explicitly permit `src/endure/MockXVS.sol` and `test/endure/venus/RewardFacetEnable.t.sol`. Carve-out enforced via `--exclude-dir=venus` in grep + explicit allow-list assertions. Recorded in FORK_MANIFEST Section 6 / Endure-authored files.
  - Rationale: future-proofing Phase 1 without changing default Phase 0.5 deployment behavior; proven enable path beats documentation-only.

### Interview Summary

**User decisions confirmed during interview**:

- **Plan file**: Overwrite `.sisyphus/plans/phase-0.5-venus-rebase.md` (the OLD outline pre-spec). The spec on line 778 mandates this regeneration.
- **Test strategy**: TDD per task (RED → GREEN → REFACTOR). Spec language is already TDD-flavored ("write failing test", "make it pass"). Plus mandatory Agent-Executed QA on top.
- **Granularity**: Aggressive splitting per Maximum Parallelism Principle — 5–8 tasks per wave, ~48 total TODOs.
- **Chunk 4 structure**: Per-subsystem tasks (one per Hardhat test directory: Comptroller/Diamond, VToken, VAI, Prime, XVS, VRT, Liquidator, Swap, DelegateBorrowers, Lens, Utils, Admin) — ~12–14 tasks, each independently verifiable via `pnpm hardhat test --grep <subsystem>`.
- **High accuracy mode**: YES — Momus loop until OKAY verdict.

### Research Findings

**Stage A complete state** (verified in repo):
- `src/venus-staging/` populated with full Venus tree at commit `6400a067` (Comptroller/, Tokens/, InterestRateModels/, Lens/, Oracle/, VAIVault/, XVSVault/, VRTVault/, PegStability/, Prime/, Liquidator/, Swap/, DelegateBorrowers/, FlashLoan/, Admin/, Governance/, Utils/, Tokens/, lib/, external/, test/).
- `src/endure/MockResilientOracle.sol` (79 LOC) and `src/endure/AllowAllAccessControlManager.sol` (78 LOC) exist — DO NOT re-author per finding F8.
- `lib/venusprotocol-*` 5 packages vendored (governance-contracts, oracle, protocol-reserve, solidity-utilities, token-bridge).
- `test/endure/venus/VenusDirectLiquidationSpike.t.sol` exists with 7 passing tests and the spike's 61-selector facet cut helpers (`_buildFacetCut`, `_marketFacetSelectors`, `_policyFacetSelectors`, `_setterFacetSelectors`, `_rewardFacetSelectors`) — used as the STARTING POINT for T8/T9's 71-selector expansion.
- `foundry.toml`: `auto_detect_solc = true`, `evm_version = "cancun"`, optimizer 200 runs, fuzz 256, invariant 1000×50.
- `remappings.txt`: longest-prefix-layered OZ + 5 `@venusprotocol/*` entries (per finding F7).

**Phase 0 Endure test inventory** (to be ported in Chunk 3):
- `test/endure/EnduRateModelParams.t.sol`
- `test/endure/MockAlpha.t.sol`
- `test/endure/MockPriceOracle.t.sol` (DELETE — replaced by Venus oracle behavior)
- `test/endure/RBACSeparation.t.sol`
- `test/endure/SeedDeposit.t.sol`
- `test/endure/WTAO.t.sol`
- `test/endure/integration/AliceLifecycle.t.sol`
- `test/endure/integration/Liquidation.t.sol`
- `test/endure/invariant/InvariantSolvency.t.sol` + `handlers/` subdir

**Existing Phase 0 deploy helper**: `packages/contracts/test/helper/EndureDeployHelper.sol` (Moonwell-flavored) + `packages/contracts/test/helper/BaseTest.t.sol` + `SimplePriceOracle.sol`.

**Existing CI pipeline** (`.github/workflows/ci.yml`):
- `contracts-build`: `forge build --root packages/contracts`
- `contracts-test`: `forge test --root packages/contracts -v` + `gas-snapshot-check.sh`
- `forbidden-patterns`: `check-forbidden-patterns.sh`
- `stance-b-audit`: clones upstream at `.upstream-sha`, byte-compares
- `e2e-smoke`: anvil + `forge script src/DeployLocal.s.sol` + `e2e-smoke.sh`
- `pnpm-workspace`: SDK/frontend/keeper

**Existing scripts**: `scripts/e2e-smoke.sh`, `scripts/check-forbidden-patterns.sh`, `scripts/gas-snapshot-check.sh`. Stance B audit script lives in `.github/workflows/ci.yml` inline.

**Spike `setUp` already implements the deployment pattern** Chunk 2 needs to promote into the reusable helper: `_deployMocks` → `_deployDiamondAndFacets` → `_wireDiamondPolicy` → `_deployMarkets` → `_supportAndConfigureMarkets` → `_seedSupply`. The 61 spike selectors are already enumerated in spike helpers and serve as the STARTING POINT (NOT the final cut) for T8/T9's 71-selector expansion.

### Pre-Plan Gap Analysis (self-applied from spec risks/mitigations)

The spec's own risk table (lines 740–757) plus findings F1–F10 plus the 21 final-state success criteria provide the gap inventory. Key items that became explicit guardrails in this plan:

- CI must stay green throughout EXCEPT during Chunk 5b: the Chunk 5b PR may contain TWO red intermediate commits (A=delete-Moonwell, B1=mass-move) — the merge gate is B2 + full CI green. All other chunk PRs must close green at every commit.
- Mass-move (Chunk 5b) MUST be 3 atomic commits per Metis recommendation: A (delete Moonwell) → B1 (structural mass-move + Hardhat/audit updates) → B2 (dual-helper teardown + Foundry green restored) — so revert is mechanical AND review-friendly.
- The 23-step deploy sequence in Chunk 2 has hard ordering constraints: oracle prices BEFORE nonzero CF/LT; lens registered BEFORE markets supported; ACM wired BEFORE caps set.
- The borrow cap semantic flip (Venus: `borrowCap == 0` disables; Moonwell: unlimited) requires a net-new test AND a behavior-mapping row for any Phase 0 cap test.
- The 3 broken Venus harness files (VRTConverterHarness, VRTVaultHarness, XVSVestingHarness) decision deferred to Chunk 4 task: re-vendor with Hardhat resolution preferred (per F5), patch as documented Stance B exception is acceptable fallback.
- `lib/venusprotocol-*` packaging: spec accepts plain copy as Stage A simplification; Chunk 1 task documents the version pin in `FORK_MANIFEST.md` (does NOT mandate submodule conversion — that is an explicit non-goal of this plan).
- Hardhat ↔ Foundry deployment state must remain isolated. No shared `addresses.json`. Endure's `addresses.json` is Foundry/Anvil only; Hardhat fixtures write to `deployments/hardhat/`.
- Behavior-mapping table is CI-enforced via `scripts/check-test-mapping.sh` (new) — fails CI if any deleted Phase 0 test path lacks a mapping row in `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`.

---

## Work Objectives

### Core Objective

Replace Endure's Phase 0 Moonwell v2 lending chassis with a Venus Protocol Core Pool chassis vendored byte-identical to commit `6400a067`, while preserving all Phase 0 behavior (TAO-only borrow asset, alpha-collateral-only markets, pooled multi-collateral health, deployer EOA admin, mock oracle, mock alpha, mock WTAO, Foundry-canonical Anvil deployment, Stance B audit posture, gas snapshot CI). Add Hardhat side-by-side hosting the upstream Venus test suite.

### Concrete Deliverables

- `packages/contracts/hardhat.config.ts` + `tsconfig.json` + updated `package.json` (Hardhat side)
- `packages/contracts/tests/hardhat/` (vendored Venus non-fork tests, ~37 files across 12 subsystems)
- `packages/contracts/deploy/` (vendored Venus hardhat-deploy scripts)
- `packages/contracts/src/test-helpers/venus/` (vendored Venus `contracts/test/` helpers)
- Rewritten `packages/contracts/test/helper/EndureDeployHelper.sol` deploying Venus chassis
- Rewritten `packages/deploy/src/DeployLocal.s.sol` deploying Venus chassis
- Ported Foundry tests: `AliceLifecycle.t.sol`, `Liquidation.t.sol`, `SeedDeposit.t.sol`, `RBACSeparation.t.sol`, `EnduRateModelParams.t.sol`, `MockAlpha.t.sol`, `WTAO.t.sol`, `invariant/InvariantSolvency.t.sol`, `invariant/handlers/EndureHandler.sol`
- Net-new Venus-semantic tests: `test/endure/venus/Lifecycle.t.sol` (renamed from spike), `LiquidationThreshold.t.sol`, `CollateralFactorOrdering.t.sol`, `BorrowCapSemantics.t.sol`, `DiamondSelectorRouting.t.sol`, `Deploy.t.sol`
- Deletion: `src/MockPriceOracle.sol`, all Moonwell `.sol` files in `src/`, `src/rewards/`, Moonwell-specific `lib/` entries, Moonwell-specific `proposals/` artifacts
- New file: `docs/briefs/phase-0.5-venus-rebase-test-mapping.md` (Phase 0 → Venus test mapping table)
- New file: `packages/contracts/tests/hardhat/SKIPPED.md` (skipped Hardhat tests + rationale)
- New script: `scripts/check-test-mapping.sh` (CI enforcement)
- Updated CI: `.github/workflows/ci.yml` adds `contracts-hardhat-build`, `contracts-hardhat-test`; `stance-b-audit` repointed; `e2e-smoke` Venus-aware; `forbidden-patterns` updated for Moonwell remnant scan
- Updated scripts: `scripts/e2e-smoke.sh` Venus-rewritten; `scripts/check-forbidden-patterns.sh` Moonwell remnant patterns; `.gas-snapshot` rebaselined
- Rewritten docs: `README.md` (root), `packages/contracts/README.md`, `packages/contracts/UPSTREAM.md`, `packages/contracts/FORK_MANIFEST.md`, `skills/endure-architecture/SKILL.md`
- Rewritten `packages/contracts/.upstream-sha`: `8d5fb1107babf7935cfabc2f6ecdb1722547f085` → `6400a067114a101bd3bebfca2a4bd06480e84831`
- Final: squash-merge to `main`, with TWO archival tags: `phase-0-moonwell-final` (pre-merge `main`) AND `v0.5.0-venus` (post-merge squash commit)

### Definition of Done

All 21 final-state success criteria from spec section "Final-state success criteria" (lines 716–738) hold. Concretely:

- [ ] `forge build --root packages/contracts` exits 0
- [ ] `forge test --root packages/contracts` exits 0
- [ ] `pnpm --filter @endure/contracts hardhat compile` exits 0
- [ ] `pnpm --filter @endure/contracts hardhat test` exits 0
- [ ] `forge script packages/deploy/src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast` succeeds against Anvil
- [ ] `scripts/e2e-smoke.sh` exits 0 (mint → approve → enterMarkets → borrow → repay → redeem against Venus)
- [ ] `test/endure/venus/LiquidationThreshold.t.sol` passes (LT used for liquidation eligibility separately from CF)
- [ ] `test/endure/venus/Lifecycle.t.sol` passes including direct vToken liquidation with `liquidatorContract == address(0)`
- [ ] `test/endure/venus/CollateralFactorOrdering.t.sol` passes (`setCollateralFactor` rejects LT < CF; rejects when oracle unset)
- [ ] `test/endure/venus/BorrowCapSemantics.t.sol` passes (`borrowCap == 0` disables borrowing)
- [ ] `test/endure/invariant/InvariantSolvency.t.sol` passes 1000 runs × 50 depth
- [ ] Stance B byte-identity audit passes against pinned commit `6400a067` for every vendored file
- [ ] Forbidden-patterns scan passes (no Moonwell remnants in `src/` outside comments/`FORK_MANIFEST.md`)
- [ ] Behavior-mapping table covers every deleted Phase 0 test (CI-enforced)
- [ ] Gas snapshot passes against new Venus baseline
- [ ] `FORK_MANIFEST.md`, `UPSTREAM.md`, `packages/contracts/README.md`, `skills/endure-architecture/SKILL.md` reflect Venus
- [ ] `packages/contracts/src/venus-staging/` does NOT exist (final move complete)
- [ ] No Moonwell `.sol` files exist under `packages/contracts/src/` (Comptroller.sol, MToken.sol, MErc20*.sol, etc.)
- [ ] `src/endure/MockResilientOracle.sol` exists; `src/endure/MockPriceOracle.sol` does NOT exist
- [ ] Branch `phase-0.5-venus-rebase` squash-merged to `main`; tag `phase-0-moonwell-final` exists pointing AT THE PLANNING-TIME `main` SHA `de5238ef41f38fa11db000ee899f0f102c5f19e5` (NOT at-merge-time `main`); tag `v0.5.0-venus` exists pointing at the squash-merge commit (Venus genesis); both tags pushed to remote

### Must Have

- TDD per task (failing test → minimal impl → refactor)
- Stance B byte-identity for all vendored files (`src/venus-staging/**` during staging; `src/**` excluding `endure/` post-Chunk-5b)
- Oracle prices set BEFORE any nonzero CF/LT in deploy sequence
- ComptrollerLens deployed and registered via `_setComptrollerLens` BEFORE markets are listed
- All 71 Diamond selectors registered in initial `diamondCut` (spike's 61-selector cut is the STARTING POINT, expanded per T8 with +10 additions: 2 MarketFacet getters, 1 PolicyFacet, 1 SetterFacet, 6 RewardFacet)
- Behavior-mapping table row for every deleted Phase 0 test
- Three-commit split for Chunk 5b mass-move (per Metis recommendation): (A) delete Moonwell, (B1) `git mv` + import updates + Hardhat path flip + audit script update + minimal FORK_MANIFEST update, (B2) dual-helper teardown + Foundry green restored
- Solvency invariant runs at full Phase 0 thresholds (1000 runs × 50 depth)
- Per-chunk PR into `phase-0.5-venus-rebase`; squash-merge to `main` only after all chunks green and tagged

### Must NOT Have (Guardrails)

- **No Moonwell remnants in `src/endure/`**: forbidden-pattern scan rejects `MToken`, `MErc20`, `MErc20Delegator`, `mWell`, `WELL`, `xWELL` outside `FORK_MANIFEST.md`/comments
- **No re-authoring of MockResilientOracle or AllowAllAccessControlManager** (finding F8) — they exist
- **No Bittensor precompile integration** (out of Phase 0.5 scope)
- **No production rewards by default** — RewardFacet deployed and FULLY FUNCTIONAL: all external reward paths (`claimVenus` overloads, `_grantXVS`, `seizeVenus`, `_setVenusSpeeds`, `_setXVSToken`, `getXVSAddress`, `getXVSVTokenAddress`, `venusSupplySpeeds`, `venusBorrowSpeeds`) are registered as Diamond selectors and callable through the unitroller proxy. Internal distribution math (`updateAndDistributeRewardsInternal`, `setVenusSpeedInternal`, `grantVenusInternal`) executes within `claimVenus`/`_setVenusSpeeds` calls — no separate selector needed. Reward speeds default to zero; admin opts in via the helper's `enableVenusRewards(...)` (see T11). This method MUST be tested end-to-end to prove the rewards path actually works (see T22b).
- **No external Liquidator on Endure Anvil deployment** — direct vToken liquidation only
- **No flash loans exposed** to Endure users (FlashLoanFacet vendored, NOT registered in Endure's diamondCut)
- **No isolated pools** — Venus Core Pool only
- **No XVS / Prime / VAI as Endure features** — vendored byte-identical, deployed in Hardhat fixtures only
- **No Hardhat ↔ Foundry shared deployment state** — separate `addresses.json` universes
- **No SDK / frontend / keeper changes** except stale Moonwell naming/docs cleanup
- **No re-discovery of Stage A findings F1–F10** — treat as facts; reference them in tasks
- **No new `test-foundry/` directory** (finding F10 — spike is already at Stage-B-final location)
- **No re-introduction of `@test-foundry/` remapping** (removed in commit `a71392a`)
- **No skipping the behavior-mapping table** (CI-enforced via `check-test-mapping.sh`)
- **No `solc_version = "0.8.25"` pin until Chunk 5b** — `auto_detect_solc = true` is mandatory through staging period (finding F6)
- **No premature deletion of Moonwell** — Phase 0 chassis must remain compilable until Chunk 5b commit A
- **No mass-move commit that bundles delete + move + helper-teardown** — must be 3 atomic commits (A + B1 + B2)
- **No deployment of ProtocolShareReserve** unless a tested runtime path requires it (Decision #9 — lazy)
- **No promotion of `lib/venusprotocol-*` to git submodules in this plan** (out of scope; plain copy is acceptable; document version pins in `FORK_MANIFEST.md`)
- **No bypass of TDD discipline**: every task must have a failing test BEFORE the implementation
- **No premature deletion of Stage A `VenusDirectLiquidationSpike.t.sol`** until Chunk 3 has a renamed/folded `test/endure/venus/Lifecycle.t.sol` covering the same gates

---

## Verification Strategy (MANDATORY)

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.
> Acceptance criteria requiring "user manually tests/confirms" are FORBIDDEN.

### Test Decision

- **Infrastructure exists**: YES (Foundry + spike tests already passing)
- **Automated tests**: YES — TDD per task (RED → GREEN → REFACTOR)
- **Framework**: Foundry (`forge test`) for Endure tests + Hardhat (`pnpm hardhat test`) for vendored Venus upstream tests
- **If TDD**: Each implementation task starts with `forge test ... --match-test <name>` failing, then minimal impl makes it pass, then refactor

### QA Policy

Every task MUST include agent-executed QA scenarios using the appropriate tool:

- **Solidity contracts / deploy helper**: `Bash` — `forge test --match-path/--match-test`, `forge build`, `cast call` against Anvil for live-state inspection
- **Hardhat fixtures / tests**: `Bash` — `pnpm --filter @endure/contracts hardhat compile`, `pnpm --filter @endure/contracts hardhat test --grep <subsystem>`
- **Anvil + scripts**: `Bash` — `anvil &` + `forge script ... --broadcast` + `scripts/e2e-smoke.sh`
- **CI yaml**: `Bash` — `act -j <job-name>` or push to a CI-test branch and read job result via `gh run view`
- **Stance B audit**: `Bash` — run audit script directly, parse exit code + diff output
- **Documentation**: `Bash` — `grep -r` for Moonwell remnants in changed docs; render markdown locally with `pandoc` or `glow` to verify structure

Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

---

## Execution Strategy

### Parallel Execution Waves

> Maximize throughput by grouping independent tasks into parallel waves. Each wave completes before the next begins. Target: 5–8 tasks per wave.

```
Wave 1 (Stage A verification + Hardhat scaffolding — Chunk 1):
├── T1: Verify Stage A artifacts intact (selector list, mocks, vendored tree, foundry config) [quick]
├── T2: Add hardhat.config.ts + tsconfig.json + package.json deps [quick]
├── T3: Vendor Venus tests/hardhat/ (non-fork only) verbatim [unspecified-low]
├── T4: Vendor Venus deploy/ scripts verbatim [unspecified-low]
├── T5: Vendor Venus contracts/test/ helpers → src/test-helpers/venus/ [unspecified-low]
├── T6: Add CI job contracts-hardhat-build (gate: hardhat compile exits 0) [quick]

Wave 2 (Endure deploy helper + Anvil deployment — Chunk 2):
├── T7: Write failing test test/endure/venus/Deploy.t.sol asserting full address surface [quick]
├── T8: Write failing test test/endure/venus/DiamondSelectorRouting.t.sol (71 selectors) [quick]
├── T9: Author NEW EndureDeployHelperVenus.sol — phase 1: ACM + Oracle + Lens + Unitroller + Diamond + facets + diamondCut (dual-helper strategy) [deep]
├── T10: Extend EndureDeployHelperVenus.sol — phase 2: IRMs + VBep20Immutable markets + supportMarket + setOraclePrices [deep]
├── T11: Extend EndureDeployHelperVenus.sol — phase 3: setCF/LT (post-oracle) + setLiquidationIncentive + caps + enableBorrow + seed-and-burn + enableVenusRewards [deep]
├── T12: Rewrite packages/deploy/src/DeployLocal.s.sol calling new helper + addresses.json output [quick]

Wave 3 (Foundry test port — Chunk 3):
├── T13: Create docs/briefs/phase-0.5-venus-rebase-test-mapping.md skeleton + scripts/check-test-mapping.sh + CI hook [quick]
├── T14: Port test/endure/integration/AliceLifecycle.t.sol against Venus [unspecified-high]
├── T15: Port test/endure/integration/Liquidation.t.sol against Venus (price-drop + negatives) [unspecified-high]
├── T16: Port test/endure/SeedDeposit.t.sol for vTokens [quick]
├── T17: Port test/endure/RBACSeparation.t.sol for Venus ACM-gated roles [unspecified-high]
├── T18: Port test/endure/EnduRateModelParams.t.sol + MockAlpha.t.sol + WTAO.t.sol [quick]
├── T19: Port test/endure/invariant/InvariantSolvency.t.sol + handlers/EndureHandler.sol (1000×50) [deep]
├── T20: Net-new test/endure/venus/LiquidationThreshold.t.sol (LT vs CF separation) [unspecified-high]
├── T21: Net-new test/endure/venus/CollateralFactorOrdering.t.sol (oracle-unset rejection + LT<CF rejection) [unspecified-high]
├── T22: Net-new test/endure/venus/BorrowCapSemantics.t.sol (cap=0 disables) [quick]
├── T22b: Net-new test/endure/venus/RewardFacetEnable.t.sol — prove RewardFacet rewards usable when enabled (NEW per user clarification) [unspecified-high]
├── T23: Rename Stage A spike to test/endure/venus/Lifecycle.t.sol; delete redundant scenarios [quick]
├── T24: Delete test/endure/MockPriceOracle.t.sol; populate behavior-mapping rows for ALL deleted Phase 0 tests [quick]

Wave 4 (Hardhat test port — Chunk 4, MAX PARALLEL after T25b foundation):
├── T25: Resolve 3 broken harness files (VRTConverter/VRTVault/XVSVesting); add to src/venus-staging/ or document deviation [unspecified-high]
├── T25b: Hardhat path-mapping foundation — solve once, propagate to T26-T37 (NEW; gates Wave 4 subsystems) [unspecified-high]
├── T25c: Resolve lib/venusprotocol-* git commit SHAs (NEW; gates T40 Stance B audit) [quick]
├── T26: Vendor Venus Comptroller/Diamond Hardhat tests + fixtures green [unspecified-high]
├── T27: Vendor Venus Unitroller Hardhat tests + fixtures green [quick]
├── T28: Vendor Venus VToken Hardhat tests (Immutable + Delegate + Delegator) + fixtures green [unspecified-high]
├── T29: Vendor Venus InterestRateModels Hardhat tests + fixtures green [quick]
├── T30: Vendor Venus VAI subsystem (Controller + Vault + token + PegStability) Hardhat tests + fixtures green [unspecified-high]
├── T31: Vendor Venus Prime + PrimeLiquidityProvider Hardhat tests + fixtures green [unspecified-high]
├── T32: Vendor Venus XVS (Vault + Store + token) Hardhat tests + fixtures green [unspecified-high]
├── T33: Vendor Venus VRT (Vault + Converter + token) Hardhat tests + fixtures green [unspecified-high]
├── T34: Vendor Venus Liquidator Hardhat tests + fixtures green [unspecified-high]
├── T35: Vendor Venus DelegateBorrowers (SwapDebtDelegate + MoveDebtDelegate) Hardhat tests + fixtures green [unspecified-high]
├── T36: Vendor Venus Swap (SwapRouter) Hardhat tests + fixtures green [unspecified-high]
├── T37: Vendor Venus Lens + Utils + Admin (skip VBNBAdmin if BNB-specific) Hardhat tests [unspecified-high]
├── T38: Author tests/hardhat/SKIPPED.md + add CI verifier matching it.skip invocations [quick]
├── T39: Add CI job contracts-hardhat-test (gate: hardhat test exits 0) [quick]

Wave 5 (CI + smoke + gas snapshot — Chunk 5a):
├── T40: Repoint stance-b-audit job: .upstream-sha → 6400a067; audit covers src/venus-staging/** [unspecified-high]
├── T41: Rewrite scripts/e2e-smoke.sh for Venus addresses + events + direct vToken liquidation [unspecified-high]
├── T42: Update scripts/check-forbidden-patterns.sh to scan for Moonwell remnants [quick]
├── T43: Regenerate .gas-snapshot baseline + update tolerance commentary [quick]
├── T44: Wire e2e-smoke CI job to new script + Venus deploy [quick]

Wave 6 (Mass-move + delete-Moonwell — Chunk 5b, THREE ATOMIC COMMITS per Metis split):
├── T45: Commit A — Delete all Moonwell .sol files + src/rewards/ + Moonwell lib/ + Moonwell proposals/ + archive FORK_MANIFEST Sections 1-5 (CI red EXPECTED on this commit) [unspecified-high]
├── T46: Commit B1 — git mv src/venus-staging/* src/ + bulk import path rewrite + Hardhat paths.sources flip + audit script update (test-helpers exclusion) + minimal FORK_MANIFEST + UPSTREAM steady-state (Foundry may stay RED; Hardhat green) [deep]
├── T46b: Commit B2 — Dual-helper teardown: delete old Moonwell helper, rename Venus helper, bulk struct rename (Foundry GREEN restored) [quick]

Wave 7 (Documentation — Chunk 6):
├── T47: Rewrite packages/contracts/README.md for Venus chassis + market params + deployment + test suites [writing]
├── T48: Rewrite packages/contracts/UPSTREAM.md to declare Venus as upstream [writing]
├── T49: Rewrite packages/contracts/FORK_MANIFEST.md for steady-state Venus layout (full file lists by section) [writing]
├── T50: Rewrite skills/endure-architecture/SKILL.md to reflect Venus-based architecture [writing]
├── T51: Update root README.md references to Venus + add Venus-specific footguns appendix [writing]

Wave FINAL (After ALL implementation tasks — 4 parallel reviews, then user okay):
├── F1: Plan compliance audit (oracle) — every Must Have implemented? every Must NOT absent?
├── F2: Code quality + build review (unspecified-high) — tsc/forge build clean, no AI slop
├── F3: Real manual QA (unspecified-high) — execute every QA scenario from every task
├── F4: Scope fidelity check (deep) — diff vs plan; no creep, no contamination

→ Present results → Wait for explicit user okay → Then tag pre-merge main as `phase-0-moonwell-final` → squash-merge to main → tag the squash commit as `v0.5.0-venus`
```

**Critical Path**: T1 → T6 → T9 → T11 → T7 (deploy green) → T14 + T15 (lifecycle/liquidation green) → T19 (invariant green) → T26 + T28 (Hardhat core green) → T30–T36 (subsystems green) → T39 (Hardhat CI green) → T41 (e2e-smoke green) → T45 → T46 (mass-move green) → F1–F4 → user okay → squash-merge

**Parallel Speedup**: ~70% faster than sequential (Waves 3 and 4 each have 7+ parallel tasks; Wave 4 peaks at 14 concurrent)
**Max Concurrent**: 14 (Wave 4)

### Dependency Matrix (abbreviated — full per-task dependencies in TODOs section)

- **T1**: blocks Wave 2 entirely (Stage A integrity gate)
- **T2–T5**: independent within Wave 1; collectively block T6
- **T6**: blocks Wave 4 (Hardhat tests need compile gate)
- **T7, T8**: independent; both block T9
- **T9** → **T10** → **T11** → **T12** (Chunk 2 deploy helper is sequential)
- **T11**: blocks T13–T24 (Wave 3 needs deploy helper)
- **T13**: blocks T24 (mapping table CI hook before final mapping rows land)
- **T14–T23, T22b**: independent within Wave 3; collectively block T24
- **T25**: blocks T33 (VRT/XVS subsystems need harness resolution)
- **T25b**: gates ALL of T26–T37 (Hardhat path mapping must work before any subsystem task can run)
- **T26–T37**: largely independent within Wave 4 (per-subsystem) — collectively blocked by T25b
- **T38, T39**: depend on T26–T37 collectively
- **T39**: blocks T44 (CI gate for Hardhat tests)
- **T40–T44**: independent within Wave 5; collectively block T45
- **T45** → **T46** → **T46b** (Chunk 5b atomic-commit ordering — A then B1 then B2)
- **T46b**: blocks T47–T51 (docs reflect steady-state layout INCLUDING canonical helper name)
- **T47–T51**: independent within Wave 7
- **F1–F4**: depend on T51 (all implementation done); independent of each other

### Agent Dispatch Summary

- **Wave 1**: 6 tasks — T1 → `quick`, T2 → `quick`, T3–T5 → `unspecified-low`, T6 → `quick`
- **Wave 2**: 6 tasks — T7, T8, T12 → `quick`, T9, T10, T11 → `deep`
- **Wave 3**: 13 tasks — T13, T16, T18, T22, T23, T24 → `quick`, T14, T15, T17, T20, T21, T22b → `unspecified-high`, T19 → `deep`
- **Wave 4**: 17 tasks — T25c, T27, T29, T38, T39 → `quick`, T25, T25b, T26, T28, T30–T37 → `unspecified-high`
- **Wave 5**: 5 tasks — T40, T41 → `unspecified-high`, T42, T43, T44 → `quick`
- **Wave 6**: 3 tasks — T45 → `unspecified-high`, T46 → `deep`, T46b → `quick`
- **Wave 7**: 5 tasks — T47–T51 → `writing`
- **FINAL**: 4 tasks — F1 → `oracle`, F2 → `unspecified-high`, F3 → `unspecified-high`, F4 → `deep`

---

## Abandon Conditions

> Cheap insurance against scope-spiral. The plan is happy-path optimized; these conditions trigger an explicit halt + reassessment rather than silent grinding.

If ANY of the following becomes true during execution, **halt and escalate to the human reviewer for a scope decision** before proceeding:

1. **Wave 4 stall**: Wave 4 (T26–T37) has fewer than 50% of subsystems green after **2 weeks** of focused execution (e.g., 6 of 12 subsystems unresolved). Likely cause: vendored Venus tests have deeper Bittensor-incompatibility than expected; consider scope-cutting Chunk 4 to defer VAI/Prime/XVS Hardhat coverage to Phase 1 (vendored-byte-identical preserved; full Hardhat coverage deferred). Spec section "Out of scope" line 767 already permits this — Endure does NOT need these as features.
2. **Stance B audit divergence**: T40's Approach A or Approach B audit reports >5 SHA mismatches that cannot be explained by documented deviations within **5 business days** of detection (gives time for upstream-history investigation). Likely cause: upstream Venus quietly published a fix; re-verify pin commit `6400a067` is still the right anchor or escalate to update the pin (a major spec change requiring re-spec).
3. **Mass-move (Chunk 5b) blocking issues**: T46 (Commit B1) cannot reach Hardhat-green within **3 days** of T45 landing (CI red expected on T45, but T46 should restore Hardhat green quickly). Likely cause: import-rewrite tooling missed paths; halt and audit T46's `sed`/`ast-grep` patterns.
4. **Solvency invariant fails after T19**: Invariant violation under handler actions at 1000×50 indicates either a real Venus chassis bug OR a port error. Halt; do NOT advance to Wave 4 until root-caused. Phase 0 invariant is non-negotiable.
5. **Stage A regression discovered mid-execution**: Any Wave reveals that Stage A's vendored tree is NOT byte-identical to upstream `6400a067` (e.g., a subtle file modification slipped in pre-planning). Halt; re-run Stance B on the staging tree before proceeding.
6. **Dual-toolchain CI runtime explosion**: If the combined `forge test` + `pnpm hardhat test` job runtime exceeds **30 minutes** in CI for any normal-sized PR, scope-cut Hardhat parallelism (e.g., split per-subsystem matrix) before Wave 5.

**Escalation protocol**: pause execution, post a status report to the Sisyphus boulder file noting which abandon condition tripped, attach evidence (logs from `.sisyphus/evidence/`), and wait for human decision. DO NOT silently re-spec, lower acceptance criteria, or skip blocked tasks.

---

## TODOs

> Implementation + Test = ONE Task. Never separate. EVERY task has Recommended Agent Profile + Parallelization info + QA Scenarios.

### Wave 1 — Stage A verification + Hardhat scaffolding (Chunk 1)

- [x] 1. **Verify Stage A artifacts intact**

  **What to do** (per Path Conventions: bare `src/`, `test/`, `lib/`, `foundry.toml`, `remappings.txt` resolve to `packages/contracts/...`):
  - Confirm `packages/contracts/src/venus-staging/` exists and matches commit `6400a067` byte-identically (run Stance B audit script against the existing tree)
  - Confirm `packages/contracts/src/endure/MockResilientOracle.sol` (79 LOC, implements `ResilientOracleInterface`) and `packages/contracts/src/endure/AllowAllAccessControlManager.sol` (78 LOC, implements `IAccessControlManagerV8` + `IAccessControl`) exist
  - Confirm `packages/contracts/lib/venusprotocol-{governance-contracts,oracle,protocol-reserve,solidity-utilities,token-bridge}/` populated
  - Confirm `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol` exists and 7 tests pass
  - Confirm `packages/contracts/foundry.toml` has `auto_detect_solc = true` + `evm_version = "cancun"`
  - Confirm `packages/contracts/remappings.txt` has the longest-prefix-layered OZ entries + 5 `@venusprotocol/*` entries
  - Run `forge test --root packages/contracts` → all 59 tests (52 Phase 0 Moonwell + 7 Venus spike) pass

  **Must NOT do**:
  - Do NOT modify any vendored file (Stance B violation)
  - Do NOT re-author `MockResilientOracle.sol` or `AllowAllAccessControlManager.sol` (finding F8)

  **Recommended Agent Profile**:
  - **Category**: `quick` — Pure verification, no implementation
  - **Skills**: `[]` — No special skills needed; `Bash` + `Read` sufficient
  - **Skills Evaluated but Omitted**: `verification-before-completion` — overkill for a single-task gate

  **Parallelization**:
  - **Can Run In Parallel**: NO — gates entire plan
  - **Parallel Group**: Wave 1 first task; blocks T2–T6 from merging
  - **Blocks**: All subsequent tasks
  - **Blocked By**: None — start immediately

  **References**:

  **Pattern References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:9-30` — Stage A status declaration with evidence paths

  **API/Type References**:
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol:_buildFacetCut` — canonical 60-selector facet cut input

  **External References**:
  - Venus pin: `6400a067114a101bd3bebfca2a4bd06480e84831` (tag `v10.2.0-dev.5`)
  - Endure stance: `packages/contracts/.upstream-sha`

  **WHY Each Reference Matters**:
  - Spec Stage A section is the contract for what "intact" means; deviating means Stage A regression that must be fixed BEFORE Stage B starts.
  - Spike `_buildFacetCut` is the canonical input for Chunk 2's deploy helper rewrite (T9).

  **Acceptance Criteria**:
  - [ ] `forge test --root packages/contracts` exits 0 with ≥59 tests passing
  - [ ] `forge build --root packages/contracts` exits 0
  - [ ] `git status` clean (no inadvertent file changes)
  - [ ] Stance B audit passes for `src/venus-staging/**` against pinned commit

  **QA Scenarios**:

  ```
  Scenario: Stage A artifacts present and tests green
    Tool: Bash
    Preconditions: Branch phase-0.5-venus-rebase, clean working tree
    Steps:
      1. Run: ls packages/contracts/src/endure/MockResilientOracle.sol packages/contracts/src/endure/AllowAllAccessControlManager.sol
      2. Run: ls packages/contracts/src/venus-staging/Comptroller/Diamond/Diamond.sol
      3. Run: ls packages/contracts/lib/venusprotocol-governance-contracts packages/contracts/lib/venusprotocol-oracle packages/contracts/lib/venusprotocol-protocol-reserve packages/contracts/lib/venusprotocol-solidity-utilities packages/contracts/lib/venusprotocol-token-bridge
      4. Run: forge test --root packages/contracts 2>&1 | tee .sisyphus/evidence/task-1-forge-test.log
      5. Assert log contains "Suite result: ok" for VenusDirectLiquidationSpike.t.sol with "7 passed"
      6. Assert log shows total "passed: 59" or higher
    Expected Result: All 4 file listings succeed, forge test exits 0 with ≥59 passing tests
    Failure Indicators: Missing file, ENOENT, "Suite result: FAILED", any test count below 59
    Evidence: .sisyphus/evidence/task-1-forge-test.log

  Scenario: Stance B audit clean for vendored Venus tree (pre-T40 — script may not yet exist)
    Tool: Bash
    Preconditions: Stage A complete; T40 has NOT yet run (script `scripts/check-stance-b.sh` does NOT exist yet)
    Steps:
      1. Replicate the inline audit logic from `.github/workflows/ci.yml` `stance-b-audit` job manually OR push to a CI-test branch and read job result via `gh run view`
      2. Run audit against `src/venus-staging/` vs upstream Venus checkout at `6400a067`
      3. Capture exit code and any diff output
    Expected Result: Exit code 0; no SHA mismatches reported
    Failure Indicators: Any SHA mismatch, any orphan file under `src/venus-staging/`
    Evidence: .sisyphus/evidence/task-1-stance-b-audit.log
    Note: After T40, this verification uses `bash scripts/check-stance-b.sh` directly. Pre-T40, the inline CI logic is the only available path.
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-1-forge-test.log`
  - [ ] `.sisyphus/evidence/task-1-stance-b-audit.log`

  **Commit**: NO (verification-only)

- [x] 2. **Add Hardhat config + TypeScript + package.json deps**

  **What to do**:
  - Create `packages/contracts/hardhat.config.ts` registering solc 0.5.16 (with `^0.5.16` dispatch to 0.5.17) AND solc 0.8.25 with cancun, paths.tests = `tests/hardhat`, paths.deploy = `deploy`, paths.deployments = `deployments`, networks.hardhat (in-memory), `hardhat-deploy` plugin imported
  - Create `packages/contracts/tsconfig.json` matching Venus upstream (`module: commonjs`, `target: es2020`, strict, `outDir: typechain-types`, includes `tests/hardhat/**/*`, `deploy/**/*`, `hardhat.config.ts`)
  - Modify `packages/contracts/package.json` to add devDependencies: `hardhat ^2.19.0`, `hardhat-deploy ^0.11.45`, `@nomicfoundation/hardhat-toolbox ^4.0.0`, `ethers ^6.10.0`, `chai ^4.3.10`, `@types/chai`, `@types/mocha`, `@types/node`, `typescript ^5.3.0`, `ts-node`. Match Venus upstream `package.json` versions where they overlap
  - Modify `packages/contracts/.gitignore` to add `artifacts/`, `cache_hardhat/`, `deployments/localhost/`, `typechain-types/`

  **Must NOT do**:
  - Do NOT touch `foundry.toml` — Foundry remains primary; Hardhat is additive
  - Do NOT add hardhat as a `dependency` (must be `devDependency`)
  - Do NOT add `hardhat.config.js` (TypeScript only — match Venus upstream)
  - Do NOT add networks beyond `hardhat` (no mainnet, no testnet — out of scope)

  **Recommended Agent Profile**:
  - **Category**: `quick` — Boilerplate config + dep additions, no logic
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent of T3, T4, T5
  - **Parallel Group**: Wave 1 (with T3, T4, T5)
  - **Blocks**: T6 (CI gate needs config in place)
  - **Blocked By**: T1

  **References**:

  **External References**:
  - Venus upstream `hardhat.config.ts` at commit `6400a067` — copy compiler config
  - Venus upstream `package.json` at commit `6400a067` — copy devDependency versions

  **Pattern References**:
  - `packages/contracts/foundry.toml` — note `evm_version = "cancun"` (Hardhat must match)

  **WHY Each Reference Matters**:
  - Venus upstream config is the proven dual-compiler setup; deviation risks compile failures on legacy 0.5.16 sources
  - EVM version mismatch between Foundry and Hardhat causes silent bytecode divergence

  **Acceptance Criteria**:
  - [ ] `pnpm --filter @endure/contracts install` succeeds
  - [ ] `pnpm --filter @endure/contracts hardhat --version` prints version
  - [ ] `cat packages/contracts/hardhat.config.ts | grep "0.5.16"` returns ≥1 match
  - [ ] `cat packages/contracts/hardhat.config.ts | grep "0.8.25"` returns ≥1 match
  - [ ] `cat packages/contracts/hardhat.config.ts | grep "cancun"` returns ≥1 match

  **QA Scenarios**:

  ```
  Scenario: Hardhat config dual-compiler ready
    Tool: Bash
    Preconditions: T1 complete; clean working tree on phase-0.5-venus-rebase
    Steps:
      1. Run: pnpm --filter @endure/contracts install 2>&1 | tee .sisyphus/evidence/task-2-install.log
      2. Run: pnpm --filter @endure/contracts hardhat --version 2>&1 | tee .sisyphus/evidence/task-2-hardhat-version.log
      3. Run: grep -E "(0\.5\.16|0\.8\.25|cancun|hardhat-deploy)" packages/contracts/hardhat.config.ts | tee .sisyphus/evidence/task-2-config-grep.log
    Expected Result: install exits 0, hardhat version prints, all 4 grep patterns match
    Failure Indicators: Install error, hardhat command not found, missing compiler/evm/plugin in config
    Evidence: .sisyphus/evidence/task-2-{install,hardhat-version,config-grep}.log

  Scenario: Foundry untouched after Hardhat addition
    Tool: Bash
    Preconditions: T2 implementation done
    Steps:
      1. Run: forge build --root packages/contracts 2>&1 | tee .sisyphus/evidence/task-2-forge-build.log
      2. Run: forge test --root packages/contracts 2>&1 | tail -20 | tee .sisyphus/evidence/task-2-forge-test-tail.log
    Expected Result: forge build exits 0; forge test still shows ≥59 passing
    Failure Indicators: Foundry build error, test count regression
    Evidence: .sisyphus/evidence/task-2-forge-{build,test-tail}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-2-install.log`
  - [ ] `.sisyphus/evidence/task-2-hardhat-version.log`
  - [ ] `.sisyphus/evidence/task-2-config-grep.log`
  - [ ] `.sisyphus/evidence/task-2-forge-build.log`
  - [ ] `.sisyphus/evidence/task-2-forge-test-tail.log`

  **Commit**: YES
  - Message: `chore(contracts): add hardhat config + ts dependencies`
  - Files: `packages/contracts/hardhat.config.ts`, `packages/contracts/tsconfig.json`, `packages/contracts/package.json`, `packages/contracts/.gitignore`, `pnpm-lock.yaml`
  - Pre-commit: `forge build --root packages/contracts && forge test --root packages/contracts`

- [x] 3. **Vendor Venus tests/hardhat/ (non-fork only)**

  **What to do**:
  - Clone Venus upstream at commit `6400a067` to a temporary directory
  - Copy `<venus>/tests/hardhat/` → `packages/contracts/tests/hardhat/` byte-identical EXCEPT `tests/hardhat/Fork/` (skip entirely)
  - Verify file count matches expectations (~37 non-fork test files across subsystems: Comptroller/, Diamond/, Unitroller/, VToken/, InterestRateModels/, VAI/, Prime/, XVS/, VRT/, Liquidator/, DelegateBorrowers/, Swap/, Lens/, Utils/, Admin/)
  - Add a top-level `tests/hardhat/README.md` explaining vendoring + skip rationale (1 paragraph)
  - DO NOT run the tests yet — Hardhat fixtures don't exist until T4

  **Must NOT do**:
  - Do NOT vendor `tests/hardhat/Fork/**` (mainnet-fork tests, not portable per spec line 663–665)
  - Do NOT modify any vendored test file (Stance B violation)
  - Do NOT add the vendored files to a single mega-commit — keep this scoped to vendoring

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low` — Mechanical copy with one exclusion
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent of T2, T4, T5
  - **Parallel Group**: Wave 1 (with T2, T4, T5)
  - **Blocks**: T6 (CI gate verifies these compile)
  - **Blocked By**: T1

  **References**:

  **External References**:
  - Venus upstream `tests/hardhat/` at commit `6400a067`

  **Pattern References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:560-567` — Chunk 4 acceptance + Fork skip mandate

  **WHY Each Reference Matters**:
  - Spec mandates 37 non-fork tests; Fork tests fail without BSC mainnet RPC

  **Acceptance Criteria**:
  - [ ] `find packages/contracts/tests/hardhat -name "*.ts" -not -path "*/Fork/*" | wc -l` ≥ 37
  - [ ] `find packages/contracts/tests/hardhat/Fork -type f 2>/dev/null | wc -l` returns 0
  - [ ] Stance B audit clean for `tests/hardhat/**` against `<venus>/tests/hardhat/**`

  **QA Scenarios**:

  ```
  Scenario: Vendored Hardhat tests present and Fork excluded
    Tool: Bash
    Preconditions: T1 complete
    Steps:
      1. Run: find packages/contracts/tests/hardhat -name "*.ts" | wc -l | tee .sisyphus/evidence/task-3-test-count.log
      2. Run: find packages/contracts/tests/hardhat/Fork -type f 2>/dev/null | wc -l | tee .sisyphus/evidence/task-3-fork-count.log
      3. Assert test count ≥ 37, fork count == 0
    Expected Result: ≥37 .ts test files, 0 Fork files
    Failure Indicators: Test count < 37, any Fork file present
    Evidence: .sisyphus/evidence/task-3-{test-count,fork-count}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-3-test-count.log`
  - [ ] `.sisyphus/evidence/task-3-fork-count.log`

  **Commit**: GROUPS WITH T4, T5
  - Message: `chore(contracts): vendor venus hardhat tests + deploy + helpers`
  - Files: `packages/contracts/tests/hardhat/**`
  - Pre-commit: file-count assertions above

- [x] 4. **Vendor Venus deploy/ scripts**

  **What to do**:
  - Copy `<venus>/deploy/` → `packages/contracts/deploy/` byte-identical
  - These hardhat-deploy scripts will set up VAI/Prime/XVS/Liquidator/etc. fixtures during Hardhat tests
  - Add `packages/contracts/deploy/README.md` (1 paragraph) clarifying these are Hardhat-fixture-only and NOT consumed by Endure's Foundry/Anvil deployment

  **Must NOT do**:
  - Do NOT modify any vendored deploy script (Stance B violation)
  - Do NOT call these from `packages/deploy/src/DeployLocal.s.sol` (Foundry path stays state-isolated per spec)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low` — Mechanical copy + 1 README
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent of T2, T3, T5
  - **Parallel Group**: Wave 1 (with T2, T3, T5)
  - **Blocks**: T6
  - **Blocked By**: T1

  **References**:

  **External References**:
  - Venus upstream `deploy/` at commit `6400a067`

  **Pattern References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:457-459` — `deploy/` purpose statement
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:475-477` — state separation rule

  **WHY Each Reference Matters**:
  - Spec is explicit that Foundry and Hardhat never share deployment state; this README enforces the rule textually

  **Acceptance Criteria**:
  - [ ] `find packages/contracts/deploy -type f -name "*.ts" | wc -l` ≥ 1
  - [ ] `cat packages/contracts/deploy/README.md` mentions "Hardhat-fixture-only" and "NOT consumed by Endure's Foundry"
  - [ ] Stance B audit clean for `deploy/**` against `<venus>/deploy/**`

  **QA Scenarios**:

  ```
  Scenario: Venus deploy scripts vendored
    Tool: Bash
    Preconditions: T1 complete
    Steps:
      1. Run: ls packages/contracts/deploy/ | tee .sisyphus/evidence/task-4-deploy-ls.log
      2. Run: find packages/contracts/deploy -name "*.ts" | wc -l | tee .sisyphus/evidence/task-4-deploy-count.log
      3. Assert count ≥ 1; assert README exists with isolation language
    Expected Result: At least 1 deploy script vendored, README clarifies isolation
    Failure Indicators: Empty deploy/, missing README, README missing isolation language
    Evidence: .sisyphus/evidence/task-4-deploy-{ls,count}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-4-deploy-ls.log`
  - [ ] `.sisyphus/evidence/task-4-deploy-count.log`

  **Commit**: GROUPS WITH T3, T5

- [x] 5. **Move existing Venus test helpers from `src/venus-staging/test/` → `src/test-helpers/venus/`**

  **What to do**:
  - **GROUND TRUTH**: Stage A already vendored Venus's `contracts/test/*.sol` files into `packages/contracts/src/venus-staging/test/` (verified at planning time — ~48 files total, ~47 `.sol`, including MockToken, SimplePriceOracle, ComptrollerMock, ComptrollerHarness, BEP20, FaucetToken, etc.). This is NOT a fresh-copy task — it is a MOVE task to reach the spec's steady-state path. NOTE: Earlier draft of this task referenced "~120 files" which was a stale upstream count; the verified Stage A repo state is ~47–48 files.
  - Run: `git mv packages/contracts/src/venus-staging/test packages/contracts/src/test-helpers/venus`
  - Verify zero file content changed (sha256 spot-check 5 files pre/post move)
  - Update Stance B audit script (T40) path mapping later: `src/test-helpers/venus/` ↔ `<venus>/contracts/test/` (this Wave 1 task only does the move; T40 records the mapping)
  - Update any imports in Endure-authored files that referenced `src/venus-staging/test/...` (none expected — Endure code uses `src/endure/` mocks, not vendored test helpers)
  - Run `forge build --root packages/contracts` → still succeeds (move-only operation)

  **Must NOT do**:
  - Do NOT clone Venus upstream and copy fresh — would create duplicates at both paths
  - Do NOT modify any vendored helper file content (Stance B violation)
  - Do NOT delete Phase 0's `test/helper/SimplePriceOracle.sol` yet — Chunk 5b handles Moonwell deletion
  - Do NOT leave duplicates at both paths

  **Recommended Agent Profile**:
  - **Category**: `quick` — Mechanical move + verification
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent of T2, T3, T4
  - **Parallel Group**: Wave 1 (with T2, T3, T4)
  - **Blocks**: T6
  - **Blocked By**: T1

  **References**:

  **Pattern References**:
  - `packages/contracts/src/venus-staging/test/` (current Stage A location, verified ~47–48 files)
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:344-345` — explicit steady-state path mandate (`src/test-helpers/venus/`)
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:679-680` — Stance B audit scope for these files

  **External References**:
  - Venus upstream `contracts/test/*.sol` at commit `6400a067` (the SHA-source for byte-identity audit)

  **WHY Each Reference Matters**:
  - Stage A landed these files at `src/venus-staging/test/` already; T5 is the move to the steady-state path the spec mandates
  - Stance B audit (T40) will compare these against `<venus>/contracts/test/**`, so path discipline is verifiable
  - Move (not fresh copy) preserves git history and avoids duplication

  **Acceptance Criteria**:
  - [ ] `packages/contracts/src/venus-staging/test/` does NOT exist (moved away)
  - [ ] **EXACT pre/post-move file count match**: `find packages/contracts/src/test-helpers/venus -name "*.sol" | wc -l` equals the pre-move count captured in QA Step 1 (typically ~47, but verify against actual pre-state — DO NOT use a hardcoded ≥100 gate)
  - [ ] `git log --diff-filter=R packages/contracts/src/test-helpers/venus/` shows the rename op (history preserved)
  - [ ] `forge build --root packages/contracts` exits 0 (no import breakage)
  - [ ] `forge test --root packages/contracts` still passes (no test regression)
  - [ ] sha256 of any 5 randomly chosen files matches before-vs-after move (byte-identity preserved)

  **QA Scenarios**:

  ```
  Scenario: Move preserves files + build still green
    Tool: Bash
    Preconditions: T1 complete; verified ~47–48 files exist at src/venus-staging/test/
    Steps:
      1. Run: COUNT_BEFORE=$(find packages/contracts/src/venus-staging/test -name "*.sol" | wc -l); echo "before: $COUNT_BEFORE" | tee .sisyphus/evidence/task-5-count-before.log
      2. Run: SHA_SAMPLE=$(sha256sum packages/contracts/src/venus-staging/test/MockToken.sol packages/contracts/src/venus-staging/test/ComptrollerMock.sol 2>/dev/null); echo "$SHA_SAMPLE" | tee .sisyphus/evidence/task-5-sha-before.log
      3. Run: git mv packages/contracts/src/venus-staging/test packages/contracts/src/test-helpers/venus
      4. Run: COUNT_AFTER=$(find packages/contracts/src/test-helpers/venus -name "*.sol" | wc -l); echo "after: $COUNT_AFTER" | tee .sisyphus/evidence/task-5-count-after.log
      5. Run: SHA_SAMPLE_AFTER=$(sha256sum packages/contracts/src/test-helpers/venus/MockToken.sol packages/contracts/src/test-helpers/venus/ComptrollerMock.sol); echo "$SHA_SAMPLE_AFTER" | tee .sisyphus/evidence/task-5-sha-after.log
      6. Run: ls packages/contracts/src/venus-staging/test 2>&1 | tee .sisyphus/evidence/task-5-old-path-gone.log
      7. Run: forge build --root packages/contracts 2>&1 | tee .sisyphus/evidence/task-5-forge-build.log
      8. Run: forge test --root packages/contracts 2>&1 | tail -10 | tee .sisyphus/evidence/task-5-forge-test-tail.log
      9. Assert: COUNT_BEFORE == COUNT_AFTER (exact match — do NOT use a hardcoded ≥100 gate; the verified Stage A count is ~47), sha256 unchanged (only paths in output differ), old path gone, build/test green
    Expected Result: File count preserved, byte-identity preserved, no build or test regression
    Failure Indicators: File count drift, sha256 mismatch, old path still exists (move incomplete), build error, test regression
    Evidence: .sisyphus/evidence/task-5-{count-before,sha-before,count-after,sha-after,old-path-gone,forge-build,forge-test-tail}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-5-{count-before,sha-before,count-after,sha-after,old-path-gone,forge-build,forge-test-tail}.log` (7 files)

  **Commit**: GROUPS WITH T3, T4 (commit message expanded to mention move: `chore(contracts): vendor venus hardhat tests + deploy + move test helpers to steady-state path`)

- [x] 6. **Add CI job `contracts-hardhat-build` (gate: `hardhat compile` exits 0)**

  **What to do**:
  - Modify `.github/workflows/ci.yml` to add a new job `contracts-hardhat-build` that:
    - Checks out the repo with submodules
    - Sets up Node 22 LTS (matches existing Node setup in CI)
    - Sets up pnpm
    - Runs `pnpm install --frozen-lockfile=false` at repo root
    - Runs `pnpm --filter @endure/contracts hardhat compile`
    - Caches `packages/contracts/cache_hardhat` and `packages/contracts/artifacts` for downstream jobs
  - Job runs in PARALLEL with `contracts-build` (Foundry); does not depend on `contracts-test`

  **Must NOT do**:
  - Do NOT make this job a hard gate for `contracts-test` (Foundry path independent)
  - Do NOT replace the existing `contracts-build` job
  - Do NOT skip `--frozen-lockfile=false` — pnpm-lock.yaml will change with Hardhat additions

  **Recommended Agent Profile**:
  - **Category**: `quick` — YAML edit, single job addition
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO — depends on T2 (config), T3 (vendored tests), T4 (deploy), T5 (helpers) all merged
  - **Parallel Group**: Wave 1 closer
  - **Blocks**: Wave 4 (Hardhat tests need compile gate proven first)
  - **Blocked By**: T2, T3, T4, T5

  **References**:

  **Pattern References**:
  - `.github/workflows/ci.yml` — existing job structure (e.g., `contracts-build`)
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:520-523` — Chunk 1 acceptance criteria

  **External References**:
  - Hardhat compile docs: `https://hardhat.org/hardhat-runner/docs/guides/compile-contracts`

  **WHY Each Reference Matters**:
  - Existing CI shape mandates Node 22 LTS, pnpm, root-level checkout — must match
  - Spec acceptance is "hardhat compile succeeds, no tests run yet" — exactly this job

  **Acceptance Criteria**:
  - [ ] `.github/workflows/ci.yml` contains job `contracts-hardhat-build`
  - [ ] CI job runs in parallel with `contracts-build`
  - [ ] Push to a CI-test branch and the new job exits 0 (verify with `gh run view`)
  - [ ] Local equivalent: `pnpm --filter @endure/contracts hardhat compile` exits 0

  **QA Scenarios**:

  ```
  Scenario: Hardhat compile succeeds locally
    Tool: Bash
    Preconditions: T2–T5 complete
    Steps:
      1. Run: pnpm install --frozen-lockfile=false 2>&1 | tail -20 | tee .sisyphus/evidence/task-6-install.log
      2. Run: pnpm --filter @endure/contracts hardhat compile 2>&1 | tee .sisyphus/evidence/task-6-hardhat-compile.log
      3. Assert: log contains "Compiled" and exits 0
    Expected Result: Compile succeeds for both 0.5.16 and 0.8.25 sources
    Failure Indicators: Compile error, missing remapping, plugin resolution failure
    Evidence: .sisyphus/evidence/task-6-{install,hardhat-compile}.log

  Scenario: CI job runs and passes on push
    Tool: Bash
    Preconditions: T6 implementation pushed to a CI-test branch
    Steps:
      1. Run: git push origin HEAD:ci-test-task-6
      2. Wait 2 minutes
      3. Run: gh run list --branch ci-test-task-6 --limit 1 --json status,conclusion,jobs > .sisyphus/evidence/task-6-gh-run.json
      4. Assert: contracts-hardhat-build job concluded "success"
    Expected Result: New CI job appears and passes
    Failure Indicators: Job missing, job failed, job timed out
    Evidence: .sisyphus/evidence/task-6-gh-run.json
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-6-install.log`
  - [ ] `.sisyphus/evidence/task-6-hardhat-compile.log`
  - [ ] `.sisyphus/evidence/task-6-gh-run.json`

  **Commit**: YES
  - Message: `ci(contracts): add hardhat compile gate`
  - Files: `.github/workflows/ci.yml`
  - Pre-commit: `pnpm --filter @endure/contracts hardhat compile` exits 0

---

### Wave 2 — Endure deploy helper rewrite + Anvil deployment (Chunk 2)

- [x] 7. **Write failing test `test/endure/venus/Deploy.t.sol` asserting full address surface**

  **What to do**:
  - Create `packages/contracts/test/endure/venus/Deploy.t.sol`
  - Import the new `EndureDeployHelperVenus` (which does NOT exist yet — that's the point: TDD red)
  - Call `helper.deployAll()` returning an `Addresses` struct
  - Assert each address is non-zero: `unitroller`, `comptrollerLens`, `accessControlManager`, `resilientOracle`, `marketFacet`, `policyFacet`, `setterFacet`, `rewardFacet`, `vWTAO`, `vAlpha30`, `vAlpha64`, `irmWTAO`, `irmAlpha`, `wtao`, `mockAlpha30`, `mockAlpha64`
  - Assert `unitroller != address(0)` AND `Comptroller(unitroller).comptrollerImplementation() == diamondImpl`
  - Assert `Comptroller(unitroller).comptrollerLens() == comptrollerLens`
  - Assert `Comptroller(unitroller).accessControlManager() == accessControlManager`
  - Assert each market is listed: `(bool isListed,,,,,,) = Comptroller(unitroller).markets(vWTAO); assertTrue(isListed);`
  - Run: `forge test --match-path test/endure/venus/Deploy.t.sol -vvv` → FAIL (helper doesn't exist yet)
  - Save failure log to evidence

  **Must NOT do**:
  - Do NOT implement the helper yet — that's T9–T11
  - Do NOT use the old Moonwell `EndureDeployHelper.sol` — this is a clean Venus-only test
  - Do NOT use `vm.skip(true)` — failure must be real (compile or revert)

  **Recommended Agent Profile**:
  - **Category**: `quick` — Test scaffolding, no implementation
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent of T8
  - **Parallel Group**: Wave 2 first pair (with T8)
  - **Blocks**: T9 (helper rewrite proceeds against this contract)
  - **Blocked By**: T1, T6

  **References**:

  **Pattern References**:
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol:setUp` — canonical Venus deploy sequence (use as input for asserting expected addresses)
  - `packages/contracts/test/helper/EndureDeployHelper.sol` — Phase 0 helper interface (informs `Addresses` struct shape conceptually, but content is Venus-specific)

  **API/Type References**:
  - `src/venus-staging/Comptroller/ComptrollerStorage.sol` — fields `comptrollerImplementation`, `comptrollerLens`, `accessControlManager`
  - `src/venus-staging/Comptroller/ComptrollerStorage.sol::markets` — 7-tuple return (finding F4)
  - `src/endure/MockResilientOracle.sol` — `ResilientOracleInterface` consumer
  - `src/endure/AllowAllAccessControlManager.sol` — `IAccessControlManagerV8` consumer

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:528-538` — Chunk 2 deliverables incl. address struct + 23-step sequence

  **WHY Each Reference Matters**:
  - Spike `setUp` is the working canonical pattern; deploy helper is essentially that pattern hoisted into a reusable contract
  - Finding F4 mandates 7-tuple decode; using 3-tuple silently fails

  **Acceptance Criteria**:
  - [ ] File `test/endure/venus/Deploy.t.sol` exists
  - [ ] `forge test --match-path test/endure/venus/Deploy.t.sol -vvv` exits NON-ZERO (compile error or test failure — both acceptable)
  - [ ] Failure mentions `EndureDeployHelperVenus` not found OR `deployAll` not callable

  **QA Scenarios**:

  ```
  Scenario: TDD red — test file written, fails as expected
    Tool: Bash
    Preconditions: T1, T6 complete; old Phase 0 EndureDeployHelper.sol still in place
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/venus/Deploy.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-7-red.log
      2. Assert: exit code != 0
      3. Assert: log mentions either "Identifier not found" / "function deployAll" / runtime revert
    Expected Result: Test fails (RED)
    Failure Indicators: Test passes (means helper accidentally already does the right thing — investigate); compile error in unrelated file
    Evidence: .sisyphus/evidence/task-7-red.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-7-red.log`

  **Commit**: GROUPS WITH T8
  - Message: `test(endure): add deploy + diamond selector failing tests`
  - Files: `packages/contracts/test/endure/venus/Deploy.t.sol`, `DiamondSelectorRouting.t.sol`
  - Pre-commit: both tests fail (RED)

- [x] 8. **Write failing test `test/endure/venus/DiamondSelectorRouting.t.sol` (71 selectors)**

  **What to do**:
  - Create `packages/contracts/test/endure/venus/DiamondSelectorRouting.t.sol`
  - Import the canonical selector list from `test/endure/venus/VenusDirectLiquidationSpike.t.sol::_marketFacetSelectors` + `_policyFacetSelectors` + `_setterFacetSelectors` + `_rewardFacetSelectors` AS A STARTING POINT
  - **EXPANDED selector cut per RewardFacet usability decision (T22b)** — VERIFIED against vendored code at commit `6400a067`. The cut expands across THREE facets (not just RewardFacet):
    - **MarketFacet** (+2 storage-getter selectors vs spike, total 33) — public-mapping auto-getters from `ComptrollerStorage`. Convention from finding F1: ComptrollerStorage public state-variable getters register on MarketFacet:
      - `venusSupplySpeeds(address)` — auto-generated from `ComptrollerStorage.sol:234` (`public` mapping). Required so T22b's Tests 1+2 can read the per-market XVS supply speed through the diamond.
      - `venusBorrowSpeeds(address)` — auto-generated from `ComptrollerStorage.sol:231` (`public` mapping). Required by Tests 1+2 (asserts `borrowSpeeds(vWTAO) == 0` then `> 0` after enable).
    - **PolicyFacet** (+1 selector vs spike, total 17):
      - `_setVenusSpeeds(VToken[],uint256[],uint256[])` — verified at `src/venus-staging/Comptroller/Diamond/facets/PolicyFacet.sol:477` (lives on PolicyFacet, NOT SetterFacet). Required so admin can set per-market reward speeds via the diamond.
    - **SetterFacet** (+1 selector vs spike, total 13):
      - `_setXVSToken(address)` — verified at `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol:604`. Required so admin (and `helper.enableVenusRewards`) can register the mock XVS ERC20 via the diamond. Without this, T22b's `enableVenusRewards(mockXvs, ...)` cannot route the underlying call.
    - **RewardFacet** (+6 selectors vs spike, total 8):
      - `claimVenus(address)` — line 33 (already in spike)
      - `claimVenus(address,VToken[])` — line 42 (NEW)
      - `claimVenus(address[],VToken[],bool,bool)` — line 55 (NEW)
      - `claimVenusAsCollateral(address)` — line 63 (NEW)
      - `_grantXVS(address,uint256)` — line 129 (NEW; admin grant path)
      - `seizeVenus(address[],address)` — line 143 (NEW)
      - `getXVSVTokenAddress()` — line 254 (already in spike; returns the vToken-XVS market, distinct from XVS ERC20)
      - `getXVSAddress()` — verified at `src/venus-staging/Comptroller/Diamond/facets/FacetBase.sol:234` (NEW). FacetBase is inherited by RewardFacet via XVSRewardsHelper, so the function is in RewardFacet's bytecode. Register the selector on RewardFacet by convention (groups XVS-related getters with reward functionality). Required so T22b's Test 2 assertion `getXVSAddress() == mockXvs` can route through the diamond.
    - **NOTE for executor**: Compute selectors via `bytes4(keccak256("functionName(types)"))` literals. For `VToken[]` calldata arrays, the canonical signature uses `address[]` since `VToken` is an `address`-shaped contract type. Verify each selector against `Diamond(payable(unitroller)).facetAddress(selector) == expectedFacet` in T8's test.
    - **Selector count reconciliation**: spike has exactly **61** selectors total (verified by grep). After T8/T9 expansion: 33 MarketFacet (+2 for speed getters) + 17 PolicyFacet (+1 for `_setVenusSpeeds`) + 13 SetterFacet (+1 for `_setXVSToken`) + 8 RewardFacet (+6 vs spike) = **71 selectors total**. (Earlier drafts said 67/69; corrected after verifying ALL required selectors for T22b's full enable-read-claim path including the public-mapping getters from ComptrollerStorage.)
    - **`getXVSAddress` vs `getXVSVTokenAddress` disambiguation** (NOTE for T22b): `getXVSAddress()` returns the XVS ERC20 token contract address (set via `_setXVSToken`). `getXVSVTokenAddress()` returns the vToken wrapping XVS in a vXVS market (a different concept — the market that supplies/borrows XVS). T22b's Test 2 must use `getXVSAddress()` for asserting the MockXVS address registration; do NOT conflate these two functions.
  - For each selector, assert `Diamond(payable(unitroller)).facetAddress(selector) == expectedFacet` where expectedFacet is one of {marketFacet, policyFacet, setterFacet, rewardFacet}
  - Critically include the 4-arg `liquidateCalculateSeizeTokens(address,address,address,uint256)` selector (finding F2)
  - Critically include the 3-arg variant for ComptrollerLens-internal callers (finding F2)
  - Assert ComptrollerStorage public-getter selectors register on MarketFacet by convention (finding F1: oracle(), comptrollerLens(), liquidatorContract(), etc.)
  - Run: `forge test --match-path test/endure/venus/DiamondSelectorRouting.t.sol -vvv` → FAIL (helper doesn't exist yet)
  - Save failure log

  **Must NOT do**:
  - Do NOT register FlashLoanFacet selectors (NOT in Endure's deployed surface per finding F1)
  - Do NOT use the original spike's ~12 selector subset — use the full 71-selector expanded cut
  - Do NOT manually compute selectors — use `bytes4(keccak256("..."))` literals matching spike helpers verbatim

  **Recommended Agent Profile**:
  - **Category**: `quick` — Selector enumeration, no logic
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent of T7
  - **Parallel Group**: Wave 2 first pair (with T7)
  - **Blocks**: T9
  - **Blocked By**: T1, T6

  **References**:

  **Pattern References**:
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol:_marketFacetSelectors` (and 3 sibling helpers) — copy verbatim
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol:test_DiamondRegistersRequiredCoreSelectors` — assertion pattern

  **API/Type References**:
  - `src/venus-staging/Comptroller/Diamond/Diamond.sol::facetAddress` — `(bytes4 selector) → address`
  - `src/venus-staging/Comptroller/Diamond/facets/{Market,Policy,Setter,Reward}Facet.sol` — facet types

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:36-46` — finding F1 selector breakdown
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:48-50` — finding F2 4-arg liquidateCalculateSeizeTokens

  **WHY Each Reference Matters**:
  - F1 mandates the spike's 61-selector baseline; T8/T9 expand to 71 to support T22b's reward enable+claim path. Missing any silently breaks runtime (Diamond returns address(0) → falls through to fallback → revert with no clear message)
  - F2 mandates BOTH 3-arg and 4-arg liquidate variants; missing 4-arg means VToken's liquidateBorrowFresh reverts

  **Acceptance Criteria**:
  - [ ] File `test/endure/venus/DiamondSelectorRouting.t.sol` exists
  - [ ] Test enumerates exactly **71 selectors** split across 4 facets: MarketFacet 33 (31 from spike + `venusSupplySpeeds(address)` + `venusBorrowSpeeds(address)`), PolicyFacet 17 (16 from spike + `_setVenusSpeeds`), SetterFacet 13 (12 from spike + `_setXVSToken`), RewardFacet 8 (2 from spike + 6 expansion: `claimVenus(address,VToken[])`, `claimVenus(address[],VToken[],bool,bool)`, `claimVenusAsCollateral(address)`, `_grantXVS(address,uint256)`, `seizeVenus(address[],address)`, `getXVSAddress()`). Verified spike baseline = 61; expansion delta = +10 (2 MarketFacet + 1 PolicyFacet + 1 SetterFacet + 6 RewardFacet).
  - [ ] `forge test --match-path test/endure/venus/DiamondSelectorRouting.t.sol -vvv` exits NON-ZERO
  - [ ] Test includes BOTH `liquidateCalculateSeizeTokens(address,address,address,uint256)` AND `liquidateCalculateSeizeTokens(address,address,uint256)` selectors

  **QA Scenarios**:

  ```
  Scenario: TDD red — selector test fails until helper exists
    Tool: Bash
    Preconditions: T1, T6 complete
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/venus/DiamondSelectorRouting.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-8-red.log
      2. Run: grep -c "0x" packages/contracts/test/endure/venus/DiamondSelectorRouting.t.sol | tee .sisyphus/evidence/task-8-selector-count.log
      3. Assert: forge exits non-zero
      4. Assert: selector count == 71 (exact — spike 61 + 10 expansion)
    Expected Result: Test fails (RED), ≥60 selectors enumerated
    Failure Indicators: Test passes prematurely, selector count low
    Evidence: .sisyphus/evidence/task-8-{red,selector-count}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-8-red.log`
  - [ ] `.sisyphus/evidence/task-8-selector-count.log`

  **Commit**: GROUPS WITH T7

- [x] 9. **Author NEW `EndureDeployHelperVenus.sol` — Phase 1: ACM + Oracle + Lens + Unitroller + Diamond + facets + diamondCut (DUAL-HELPER STRATEGY)**

  **What to do**:
  - **DUAL-HELPER STRATEGY (decided in interview)**: To keep Phase 0 Moonwell tests GREEN through Wave 3, this task creates a NEW file `packages/contracts/test/helper/EndureDeployHelperVenus.sol` ALONGSIDE the existing `EndureDeployHelper.sol`. The Phase 0 Moonwell helper stays UNTOUCHED and continues to serve Phase 0 Moonwell tests; the new Venus helper serves all new Venus-targeted tests (T7, T8, T14–T23). Both helpers coexist throughout Wave 3, Wave 4, Wave 5. T46b (Chunk 5b Commit B2) deletes the old Moonwell helper and renames `EndureDeployHelperVenus.sol` → `EndureDeployHelper.sol`.
  - Create `packages/contracts/test/helper/EndureDeployHelperVenus.sol` (NEW FILE)
  - New helper deploys (in order): `AllowAllAccessControlManager` → `MockResilientOracle` → `ComptrollerLens` → `Unitroller` → `Diamond` (impl) → `MarketFacet` → `PolicyFacet` → `SetterFacet` → `RewardFacet`
  - Call `Unitroller._setPendingImplementation(diamond)` then `Diamond._become(unitroller)`
  - Call `Diamond(payable(unitroller)).diamondCut(_buildFacetCut(...))` with the EXPANDED **71-selector cut** (spike's 61 + 10 additions per T8). The expansion touches FOUR facets: MarketFacet (+2: `venusSupplySpeeds(address)` + `venusBorrowSpeeds(address)` — auto-generated public-mapping getters from ComptrollerStorage), PolicyFacet (+1: `_setVenusSpeeds` at `PolicyFacet.sol:477`), SetterFacet (+1: `_setXVSToken` at `SetterFacet.sol:604`), and RewardFacet (+6: 2 new `claimVenus` overloads + `claimVenusAsCollateral` + `_grantXVS` + `seizeVenus` + `getXVSAddress` from FacetBase at `FacetBase.sol:234`). See T8 for the exact selector list with verified line numbers.
  - Expose addresses on the Venus `Addresses` struct (separate symbol from any Moonwell `Addresses` struct — namespace via library or contract name to avoid collision)
  - Make T7's `Deploy.t.sol` (which imports `EndureDeployHelperVenus`, NOT the Moonwell helper) and T8's `DiamondSelectorRouting.t.sol` PASS at this point (RED → GREEN for selector routing + facet wiring)
  - Phase 1 leaves the following null/uninitialized: lens not yet wired, oracle not wired, ACM not wired (T10 wires them), markets not deployed (T10), CF/LT not set (T11)
  - Verify: `forge test --root packages/contracts` shows ALL 52 Phase 0 Moonwell tests STILL GREEN (Phase 0 helper untouched) PLUS T7+T8 newly green

  **Must NOT do**:
  - Do NOT modify or delete the old `EndureDeployHelper.sol` — that file remains exactly as-is until T46
  - Do NOT use the same struct name `Addresses` for both helpers if it would cause a Solidity import collision; namespace as `EndureDeployHelperVenus.VenusAddresses` or via library
  - Do NOT register FlashLoanFacet
  - Do NOT use `ComptrollerMock` (spike used it; Stage A finding said move to Unitroller)
  - Do NOT inline the selector list as ad-hoc literals — define `_buildFacetCut` and 4 helpers in the new helper, starting from the spike's structure but EXPANDED per T8 (do NOT copy the spike's 60-selector cut verbatim — it's missing reward-distribution selectors that T22b needs)
  - Do NOT add governance/Timelock setup (out of Phase 0.5 scope)
  - Do NOT cause ANY Phase 0 Moonwell test regression (dual-helper invariant)

  **Recommended Agent Profile**:
  - **Category**: `deep` — Multi-step deploy with hard ordering constraints
  - **Skills**: `[test-driven-development]` (RED→GREEN discipline)
  - **Skills Evaluated but Omitted**: `verification-before-completion` — covered by built-in Acceptance Criteria

  **Parallelization**:
  - **Can Run In Parallel**: NO — sequential within Chunk 2 (T9 → T10 → T11)
  - **Parallel Group**: Sequential
  - **Blocks**: T10
  - **Blocked By**: T7, T8 (red tests must exist first)

  **References**:

  **Pattern References**:
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol:_deployDiamondAndFacets` — exact deployment sequence
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol:_wireDiamondPolicy` — ACM/oracle/lens wiring (used in T10)
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol:_buildFacetCut` — canonical cut

  **API/Type References**:
  - `src/venus-staging/Comptroller/Unitroller.sol::_setPendingImplementation` + `_acceptImplementation`
  - `src/venus-staging/Comptroller/Diamond/Diamond.sol::_become` — sets unitroller as caller
  - `src/venus-staging/Comptroller/Diamond/interfaces/IDiamondCut.sol::FacetCut` struct

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:528-538` — full Chunk 2 deliverables
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:36-46` — finding F1 selector breakdown

  **WHY Each Reference Matters**:
  - Spike `setUp` sequence is the proven, tested order; deviating risks Diamond not routing selectors correctly
  - `_become` MUST be called by the impl contract with unitroller as arg, NOT the inverse — common pitfall

  **Acceptance Criteria**:
  - [ ] `EndureDeployHelperVenus.sol` exists as a NEW file alongside the untouched `EndureDeployHelper.sol`
  - [ ] `EndureDeployHelperVenus.sol` exposes `deployAll() returns (VenusAddresses memory)` (or equivalent namespaced struct accessor)
  - [ ] `forge test --root packages/contracts` shows ALL 52 Phase 0 Moonwell tests STILL GREEN (no regression)
  - [ ] `forge test --match-path test/endure/venus/DiamondSelectorRouting.t.sol -vvv` PASSES
  - [ ] `forge test --match-path test/endure/venus/Deploy.t.sol -vvv` shows progress: address surface assertions for ACM/oracle/lens/unitroller/diamond/4 facets PASS; market-related assertions still FAIL (deferred to T10)
  - [ ] `Diamond(payable(unitroller)).comptrollerImplementation()` returns the diamond impl address

  **QA Scenarios**:

  ```
  Scenario: Diamond + facets wired and routing
    Tool: Bash
    Preconditions: T7, T8 RED logs captured
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/venus/DiamondSelectorRouting.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-9-selector-green.log
      2. Run: forge test --root packages/contracts --match-path test/endure/venus/Deploy.t.sol --match-test "test_AddressSurface" -vvv 2>&1 | tee .sisyphus/evidence/task-9-deploy-partial.log
      3. Assert: selector test exits 0
      4. Assert: deploy test shows ACM/oracle/lens/unitroller/4 facets non-zero (markets may still be zero)
    Expected Result: Selector routing GREEN, address surface partially GREEN
    Failure Indicators: Selector test still RED, ANY of {acm, oracle, lens, unitroller, diamond, 4 facets} == address(0)
    Evidence: .sisyphus/evidence/task-9-{selector-green,deploy-partial}.log

  Scenario: No regression in spike tests
    Tool: Bash
    Preconditions: T9 implementation done
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/venus/VenusDirectLiquidationSpike.t.sol 2>&1 | tee .sisyphus/evidence/task-9-spike-still-green.log
      2. Assert: 7 tests still pass
    Expected Result: Spike still 7/7 green
    Failure Indicators: Any spike test regression
    Evidence: .sisyphus/evidence/task-9-spike-still-green.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-9-selector-green.log`
  - [ ] `.sisyphus/evidence/task-9-deploy-partial.log`
  - [ ] `.sisyphus/evidence/task-9-spike-still-green.log`

  **Commit**: GROUPS WITH T10, T11
  - Message: `feat(endure): rewrite deploy helper for venus chassis`
  - Files: `packages/contracts/test/helper/EndureDeployHelperVenus.sol` (NEW file; the existing `EndureDeployHelper.sol` is NOT touched)
  - Pre-commit: T9 + T10 + T11 acceptance criteria all met

- [x] 10. **Extend `EndureDeployHelperVenus.sol` — Phase 2: wire ACM/oracle/lens + IRMs + VBep20Immutable markets + supportMarket + setOraclePrices**

  **What to do**:
  - In the helper, after Phase 1's diamondCut completes:
    - Call `Comptroller(unitroller)._setComptrollerLens(comptrollerLens)` — CRITICAL per spec line 748
    - Call `Comptroller(unitroller)._setPriceOracle(resilientOracle)`
    - Call `Comptroller(unitroller)._setAccessControl(accessControlManager)`
  - Deploy underlyings: `WTAO` (existing Endure mock), `MockAlpha30`, `MockAlpha64`
  - **PRE-DEPLOY: Update `src/endure/EnduRateModelParams.sol` for Venus's 8-param TwoKinks shape**. Phase 0's file holds 4 Moonwell-shape `uint256` constants per market. Venus's `TwoKinksInterestRateModel` constructor (verified at `src/venus-staging/InterestRateModels/TwoKinksInterestRateModel.sol:89`) takes 8 **`int256`** params (NOT `uint256`):
    ```solidity
    constructor(
        int256 baseRatePerYear_,    int256 multiplierPerYear_,    int256 kink1_,
        int256 multiplier2PerYear_, int256 baseRate2PerYear_,     int256 kink2_,
        int256 jumpMultiplierPerYear_, int256 blocksPerYear_
    )
    ```
  - **TYPE FIX (CRITICAL)**: Change ALL existing AND new IRM constants in `EnduRateModelParams.sol` from `uint256` to `int256`. Without this, the constructor call fails with implicit-conversion errors. Existing 4 constants per market must also flip to `int256`.
  - **LOCKED CONSTANT VALUES (decision table — use these EXACT values)**:

    | Constant | WTAO | Alpha30/64 | Rationale |
    |----------|------|------------|-----------|
    | `*_BASE_RATE_PER_YEAR` | `int256(0.02e18)` | `int256(0)` | Existing Phase 0 values (kept as-is) |
    | `*_MULTIPLIER_PER_YEAR` | `int256(0.10e18)` | `int256(0)` | Existing |
    | `*_JUMP_MULTIPLIER_PER_YEAR` | `int256(3e18)` | `int256(0)` | Existing |
    | `*_KINK1` | `int256(0.50e18)` | `int256(0.99e18)` | NEW. WTAO: first breakpoint at 50% util. Alpha: 0.99e18 (Venus enforces `kink2 > kink1 > 0` per `TwoKinksInterestRateModel.sol:103` — equal kinks revert with `InvalidKink`; alpha never borrows so the value is academic, but constructor must accept it) |
    | `*_KINK2` | `int256(0.80e18)` | `int256(1e18)` | NEW. WTAO: second breakpoint at 80% util (matches existing `*_KINK`). Alpha: 1e18 ensures `kink2 > kink1` |
    | `*_MULTIPLIER_2_PER_YEAR` | `int256(0.50e18)` | `int256(0)` | NEW. WTAO: medium slope between kink1 and kink2. Alpha: zero (no borrowing) |
    | `*_BASE_RATE_2_PER_YEAR` | `int256(0)` | `int256(0)` | NEW. No additive base rate at kink1 |
    | `BLOCKS_PER_YEAR` (shared) | `int256(2_628_000)` | (shared) | NEW. Bittensor EVM 12s block time → 365.25 × 86400 / 12 ≈ 2,628,000. Subject to verification at deploy time — add `// TODO: verify against actual Bittensor EVM block time at deploy` comment. |

  - Update `pragma solidity` from `0.8.19` to `0.8.25` (Venus chassis target). Verify compiles in both staging and post-T46 states.
  - The existing `*_KINK` constant becomes redundant after this update (replaced by `*_KINK2` for WTAO, ignored for alpha). Either keep `*_KINK` as an alias of `*_KINK2` (safer for downstream readers) OR remove it (cleaner). Decision: **keep as alias** (one extra line, zero risk).
  - Deploy IRMs: `TwoKinksInterestRateModel` for WTAO with the 8 Venus params from updated `EnduRateModelParams`; same for alphas (alpha IRMs keep zero-rate semantics since alphas never borrow — constructor still takes 8 args, all zeros except `KINK1=0.99e18` / `KINK2=1e18` which satisfies Venus's `kink2 > kink1 > 0` invariant per `TwoKinksInterestRateModel.sol:103`)
  - Deploy 3× `VBep20Immutable` markets: `vWTAO`, `vAlpha30`, `vAlpha64` (using respective underlyings + IRMs + Comptroller proxy)
  - Call `Comptroller(unitroller)._supportMarket(vToken)` for each
  - Set oracle prices via `MockResilientOracle.setUnderlyingPrice(vToken, price)` for ALL 3 markets — MUST happen BEFORE T11's CF/LT setting (per finding F3 + spec line 747)
  - DO NOT set CF/LT yet (deferred to T11)
  - Make T7's `Deploy.t.sol` market-listed assertions PASS

  **Must NOT do**:
  - Do NOT set CF/LT in this task — that's T11's ordering guard
  - Do NOT deploy `VBep20Delegate` or `VBep20Delegator` (spike used Immutable; Hardhat fixtures handle the others)
  - Do NOT use Phase 0's `MockPriceOracle` (DELETED in Chunk 5b; only Venus oracle here)
  - Do NOT deploy ProtocolShareReserve (Decision #9: lazy)

  **Recommended Agent Profile**:
  - **Category**: `deep` — Sequenced deployment with ordering constraints
  - **Skills**: `[test-driven-development]`

  **Parallelization**:
  - **Can Run In Parallel**: NO — sequential after T9
  - **Parallel Group**: Sequential
  - **Blocks**: T11
  - **Blocked By**: T9

  **References**:

  **Pattern References**:
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol:_deployMarkets` + `_supportAndConfigureMarkets` — exact pattern (split: support+oraclePrices in T10, CF/LT in T11)
  - `packages/contracts/src/endure/EnduRateModelParams.sol` — IRM constants

  **API/Type References**:
  - `src/venus-staging/Comptroller/Diamond/facets/MarketFacet.sol::_supportMarket(VToken)`
  - `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol::_setComptrollerLens`, `_setPriceOracle`, `_setAccessControl`
  - `src/venus-staging/Tokens/VTokens/VBep20Immutable.sol` — constructor signature
  - `src/venus-staging/InterestRateModels/TwoKinksInterestRateModel.sol` — constructor signature
  - `src/endure/MockResilientOracle.sol::setUnderlyingPrice(VToken, uint256)` — admin price setter
  - `src/endure/{WTAO,MockAlpha30,MockAlpha64}.sol` — Endure mock underlyings

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:528-538` — Chunk 2 23-step sequence
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:746-748` — risk register for ordering

  **WHY Each Reference Matters**:
  - Spike pattern is proven; constructor arg order for VBep20Immutable is non-obvious (admin, IRM, comptroller, decimals, name, symbol, exchangeRate, underlying)
  - Skipping `_setComptrollerLens` causes liquidity calculations to revert silently — Lens omission is the #1 silent footgun

  **Acceptance Criteria**:
  - [ ] `src/endure/EnduRateModelParams.sol` updated to 0.8.25 pragma; contains the 4-5 net-new Venus constants per market plus shared `BLOCKS_PER_YEAR` (or per-market) — file compiles cleanly
  - [ ] `Comptroller(unitroller).comptrollerLens()` returns the Lens address (non-zero)
  - [ ] `Comptroller(unitroller).oracle()` returns the ResilientOracle address (non-zero)
  - [ ] All 3 markets show `isListed == true` via `Comptroller(unitroller).markets(vToken)`
  - [ ] `MockResilientOracle.getUnderlyingPrice(vWTAO)` returns non-zero (and same for vAlpha30, vAlpha64)
  - [ ] CF and LT are still ZERO at end of T10 (verified in T11 setup)
  - [ ] T7's `Deploy.t.sol` address surface assertions all PASS

  **QA Scenarios**:

  ```
  Scenario: Markets listed and oracle prices set, CF/LT still zero
    Tool: Bash
    Preconditions: T9 GREEN
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/venus/Deploy.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-10-deploy.log
      2. Add a temporary inspection test (or use cast call against forge stdout) verifying: markets listed YES, oracle prices nonzero, CF == 0, LT == 0
    Expected Result: All address surface + market-listed assertions GREEN; CF/LT still zero (confirms T11 has work to do)
    Failure Indicators: Any market not listed, oracle returns 0 price, CF/LT prematurely set
    Evidence: .sisyphus/evidence/task-10-deploy.log

  Scenario: Spike still green
    Tool: Bash
    Preconditions: T10 done
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/venus/VenusDirectLiquidationSpike.t.sol 2>&1 | tee .sisyphus/evidence/task-10-spike.log
    Expected Result: 7/7 spike tests still green
    Failure Indicators: Any regression
    Evidence: .sisyphus/evidence/task-10-spike.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-10-deploy.log`
  - [ ] `.sisyphus/evidence/task-10-spike.log`

  **Commit**: GROUPS WITH T9, T11

- [x] 11. **Extend `EndureDeployHelperVenus.sol` — Phase 3: setCF/LT (post-oracle) + setLiquidationIncentive + caps + enableBorrow + seed-and-burn + enableVenusRewards**

  **What to do**:
  - In the helper, after Phase 2:
    - Call `Comptroller(unitroller).setCollateralFactor(vWTAO, 0, 0)` — CF and LT both zero (WTAO is borrow asset, not collateral). NOTE: `setCollateralFactor` has NO leading underscore in Venus (verified in `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol:217,248` — two overloads exist)
    - Call `Comptroller(unitroller).setCollateralFactor(vAlpha30, 0.25e18, 0.35e18)` — Decision #8 default
    - Call `Comptroller(unitroller).setCollateralFactor(vAlpha64, 0.25e18, 0.35e18)`
    - Verify each return code is success (0); non-zero would indicate ordering violation (oracle unset, LT<CF, etc.)
    - Set liquidation incentive PER-MARKET (Venus has per-market incentives, NOT a global one — verified at `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol:232,265` two overloads, NO leading underscore; spike calls `sf.setLiquidationIncentive(address(vAlpha), LIQUIDATION_INCENTIVE)` per-market):
      - `Comptroller(unitroller).setLiquidationIncentive(vWTAO, 1.08e18)`
      - `Comptroller(unitroller).setLiquidationIncentive(vAlpha30, 1.08e18)`
      - `Comptroller(unitroller).setLiquidationIncentive(vAlpha64, 1.08e18)`
    - Call `Comptroller(unitroller)._setCloseFactor(0.5e18)` (HAS leading underscore — verified at `SetterFacet.sol:185`)
    - Set borrow caps via SetterFacet: `_setMarketBorrowCaps([vWTAO], [type(uint256).max])`; `_setMarketBorrowCaps([vAlpha30, vAlpha64], [0, 0])` — VENUS SEMANTIC: cap 0 == disabled (NOT unlimited)
    - Set supply caps to `type(uint256).max` for all 3
    - **CRITICAL — `setIsBorrowAllowed` per-market** (verified in spike at line 171): `Comptroller(unitroller).setIsBorrowAllowed(0, address(vWTAO), true)` — this is REQUIRED to actually enable borrowing on vWTAO. Without it, `borrowAllowed` returns non-zero and ALL lifecycle borrows fail. Alpha markets stay at default `false` (collateral-only). Signature: `setIsBorrowAllowed(uint96 poolId, address vToken, bool borrowAllowed)` — `poolId == 0` is the core pool default. Verified at `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol:747`.
    - Seed each vToken: deposit `1e18` units of underlying (mint underlying to deployer first), call `vToken.mint(1e18)`, then transfer received vTokens to `0xdEaD`
  - **RewardFacet "fully functional, optional" path** (per user clarification): RewardFacet is already wired (T9 included it in diamondCut). Reward speeds remain at zero by default. ADD: helper exposes a public function `enableVenusRewards(address xvsToken, address[] calldata vTokens, uint256[] calldata supplySpeeds, uint256[] calldata borrowSpeeds, uint256 fundingAmount)` that admin can call post-deploy to fund + activate reward distribution. The function performs THREE steps in this order:
    1. `Comptroller(unitroller)._setXVSToken(xvsToken)` — register the XVS ERC20 with the comptroller
    2. `IERC20(xvsToken).transferFrom(msg.sender, address(unitroller), fundingAmount)` — transfer XVS into the comptroller so `grantVenusInternal` has tokens to distribute. Without this, `claimVenus` would silently no-op (Venus's `grantVenusInternal` reads `xvs.balanceOf(address(this))` and skips the transfer if insufficient — the call doesn't revert)
    3. `Comptroller(unitroller)._setVenusSpeeds(vTokens, supplySpeeds, borrowSpeeds)` — activate per-market reward distribution
  - Helper does NOT call `enableVenusRewards` in the default `deployAll()` path (rewards remain zero). Caller must `IERC20(xvsToken).approve(address(helper), fundingAmount)` BEFORE invoking `enableVenusRewards`. T22b proves the path works end-to-end with a mock XVS token.
  - Make T7's `Deploy.t.sol` ALL assertions PASS

  **Must NOT do**:
  - Do NOT set CF/LT BEFORE oracle prices (will fail with non-zero return code)
  - Do NOT use `vm.expectRevert` for CF/LT rejection — use return-code assertion (finding F3)
  - Do NOT skip seed-and-burn (Phase 0 invariant: every market starts non-empty)
  - Do NOT enable borrow on vAlpha markets (alpha is collateral-only per locked architecture)

  **Recommended Agent Profile**:
  - **Category**: `deep` — Sequence + return-code semantics
  - **Skills**: `[test-driven-development]`

  **Parallelization**:
  - **Can Run In Parallel**: NO — sequential after T10
  - **Parallel Group**: Sequential
  - **Blocks**: T12
  - **Blocked By**: T10

  **References**:

  **Pattern References**:
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol:_supportAndConfigureMarkets` — CF/LT setting post-oracle
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol:_seedSupply` — seed-and-burn pattern
  - `packages/contracts/test/helper/EndureDeployHelper.sol` (Phase 0 Moonwell version) — seed-and-burn target value (`1e18`) and burn address (`0xdEaD`)

  **API/Type References**:
  - `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol:217,248::setCollateralFactor(VToken, uint256, uint256)` — TWO overloads exist; both take CF + LT mantissas; return Compound soft-fail uint. NO leading underscore.
  - `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol:328::_setMarketBorrowCaps(VToken[], uint256[])` — borrow cap setter (HAS leading underscore)
  - `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol:232,265::setLiquidationIncentive` (NO leading underscore; PER-MARKET — TWO overloads: `(address,uint256)` for core pool default + `(uint96,address,uint256)` for explicit poolId)
  - `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol:185::_setCloseFactor` (HAS leading underscore; global)

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:528-538` — Chunk 2 23-step sequence
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:53-54` — finding F3 (Compound soft-fail pattern)
  - Decision #8 in spec: CF=0.25e18, LT=0.35e18

  **WHY Each Reference Matters**:
  - Compound soft-fail returns uint error code; `vm.expectRevert` would silently fail to detect the rejection
  - Borrow cap 0 in Venus DISABLES (Moonwell semantic was unlimited) — silent flip if not asserted

  **Acceptance Criteria**:
  - [ ] `Comptroller(unitroller).markets(vAlpha30)` returns 7-tuple with `collateralFactorMantissa == 0.25e18` and `liquidationThresholdMantissa == 0.35e18`
  - [ ] Same for vAlpha64
  - [ ] `Comptroller(unitroller).markets(vWTAO)` returns CF=0, LT=0
  - [ ] `Comptroller(unitroller).borrowCaps(vWTAO) == type(uint256).max`
  - [ ] `Comptroller(unitroller).borrowCaps(vAlpha30) == 0` (disabled)
  - [ ] `Comptroller(unitroller).markets(vWTAO)` 7th-tuple field (`isBorrowAllowed`) == `true` (enabled via `setIsBorrowAllowed`)
  - [ ] `Comptroller(unitroller).markets(vAlpha30)` 7th-tuple field == `false` (collateral-only; never enabled)
  - [ ] `Comptroller(unitroller).markets(vAlpha64)` 7th-tuple field == `false` (collateral-only)
  - [ ] Each vToken's `totalSupply()` ≥ initial mint (seed succeeded)
  - [ ] Each vToken's `balanceOf(0x000000000000000000000000000000000000dEaD)` > 0 (burn succeeded)
  - [ ] T7's `Deploy.t.sol` runs FULLY GREEN
  - [ ] All 59+ existing tests still pass (no regression)

  **QA Scenarios**:

  ```
  Scenario: Full deploy GREEN — all addresses, CF/LT, caps, seeds correct
    Tool: Bash
    Preconditions: T10 done
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/venus/Deploy.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-11-deploy-green.log
      2. Run: forge test --root packages/contracts 2>&1 | tail -10 | tee .sisyphus/evidence/task-11-fulltree.log
      3. Assert: Deploy.t.sol all assertions GREEN
      4. Assert: total tests passing ≥ 60 (59 prior + Deploy.t.sol counted)
    Expected Result: Full deploy surface verified
    Failure Indicators: Any market with wrong CF/LT, wrong borrow cap, missing seed
    Evidence: .sisyphus/evidence/task-11-{deploy-green,fulltree}.log

  Scenario: CF/LT setting succeeds (return code 0)
    Tool: Bash
    Preconditions: T11 done
    Steps:
      1. Add a test that captures the return value of `setCollateralFactor` (no leading underscore) and asserts == 0
      2. Run: forge test --root packages/contracts --match-test "test_CFReturnCodeZero" -vvv 2>&1 | tee .sisyphus/evidence/task-11-cf-retcode.log
    Expected Result: Return code 0 (success) for all CF/LT calls
    Failure Indicators: Non-zero return code (oracle ordering violated, LT<CF, etc.)
    Evidence: .sisyphus/evidence/task-11-cf-retcode.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-11-deploy-green.log`
  - [ ] `.sisyphus/evidence/task-11-fulltree.log`
  - [ ] `.sisyphus/evidence/task-11-cf-retcode.log`

  **Commit**: GROUPS WITH T9, T10
  - Pre-commit: full plan acceptance criteria for T9+T10+T11 all met

- [x] 12. **Rewrite `packages/deploy/src/DeployLocal.s.sol` for Venus + addresses.json output**

  **What to do**:
  - Replace `packages/deploy/src/DeployLocal.s.sol` to call the new `EndureDeployHelperVenus.deployAll()` (or its public deployment functions if the helper is library-style). After T46 the import will be auto-rewritten back to `EndureDeployHelper.deployAll()`.
  - Write resulting addresses to `packages/deploy/addresses.json` (one JSON object with: `unitroller`, `comptrollerLens`, `accessControlManager`, `resilientOracle`, `marketFacet`, `policyFacet`, `setterFacet`, `rewardFacet`, `vWTAO`, `vAlpha30`, `vAlpha64`, `irmWTAO`, `irmAlpha`, `wtao`, `mockAlpha30`, `mockAlpha64`)
  - Use `vm.serializeAddress` + `vm.writeJson` for output
  - Script must be runnable as `forge script packages/deploy/src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast --private-key $ANVIL_PK`
  - Add `deploy()` function that wraps the helper for use by both `--broadcast` (Anvil) and tests
  - Update `packages/deploy/foundry.toml` if remappings need adjustment for new helper path

  **Must NOT do**:
  - Do NOT consume any Hardhat `deployments/` directory (state isolation)
  - Do NOT write to a path Hardhat fixtures also write to
  - Do NOT inline the deploy logic — must call the helper from T9–T11

  **Recommended Agent Profile**:
  - **Category**: `quick` — Adapt existing script + JSON write
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO — sequential after T11
  - **Parallel Group**: Sequential
  - **Blocks**: Wave 3 (test port can begin once deploy helper is GREEN)
  - **Blocked By**: T11

  **References**:

  **Pattern References**:
  - `packages/deploy/src/DeployLocal.s.sol` (existing Phase 0 Moonwell version) — script structure + JSON output pattern
  - `packages/contracts/script/templates/` — any existing JSON-output patterns

  **API/Type References**:
  - `forge-std/Script.sol` — `vm.serializeAddress`, `vm.writeJson`, `vm.startBroadcast`/`stopBroadcast`

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:529` — addresses struct shape

  **WHY Each Reference Matters**:
  - Existing script's JSON output format is consumed by `e2e-smoke.sh` (T41) and downstream packages — keep schema stable except for new keys

  **Acceptance Criteria**:
  - [ ] `forge build --root packages/deploy` exits 0
  - [ ] In a fresh anvil session: `forge script packages/deploy/src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` exits 0
  - [ ] `packages/deploy/addresses.json` exists with all 16 expected keys, all values are non-zero 0x-prefixed addresses
  - [ ] On-chain state matches deployed addresses (cast call sanity check on `Comptroller(unitroller).comptrollerLens()`)

  **QA Scenarios**:

  ```
  Scenario: Anvil deploy succeeds end-to-end
    Tool: Bash
    Preconditions: T11 GREEN
    Steps:
      1. Run: anvil --port 8545 > /tmp/anvil.log 2>&1 &
      2. Sleep 2
      3. Run: forge script packages/deploy/src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 2>&1 | tee .sisyphus/evidence/task-12-deploy.log
      4. Run: jq -r 'keys | length' packages/deploy/addresses.json | tee .sisyphus/evidence/task-12-keys.log
      5. Run: jq -r '.unitroller' packages/deploy/addresses.json
      6. Run: cast call $(jq -r '.unitroller' packages/deploy/addresses.json) "comptrollerLens()(address)" --rpc-url http://localhost:8545 | tee .sisyphus/evidence/task-12-cast.log
      7. Kill anvil
    Expected Result: deploy exits 0; addresses.json has ≥16 keys; cast returns non-zero lens address
    Failure Indicators: Deploy revert, missing keys, lens returns 0x000…000
    Evidence: .sisyphus/evidence/task-12-{deploy,keys,cast}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-12-deploy.log`
  - [ ] `.sisyphus/evidence/task-12-keys.log`
  - [ ] `.sisyphus/evidence/task-12-cast.log`

  **Commit**: YES
  - Message: `feat(deploy): rewrite DeployLocal for venus`
  - Files: `packages/deploy/src/DeployLocal.s.sol`, `packages/deploy/foundry.toml` (if changed), `packages/deploy/addresses.json` (sample output committed for reference)
  - Pre-commit: full anvil deploy + cast call sanity passes

---

### Wave 3 — Foundry test port + behavior-mapping table (Chunk 3)

- [x] 13. **Create `docs/briefs/phase-0.5-venus-rebase-test-mapping.md` skeleton + `scripts/check-test-mapping.sh` + CI hook**

  **What to do**:
  - Create `docs/briefs/phase-0.5-venus-rebase-test-mapping.md` with header, intro paragraph (per spec lines 608–620), and an empty table with columns `Phase 0 test path | Behavior asserted | Venus replacement test path | Notes`
  - Pre-populate stub rows for all Phase 0 Endure tests slated for port (T14–T19): AliceLifecycle, Liquidation, SeedDeposit, RBACSeparation, EnduRateModelParams, MockAlpha, WTAO, MockPriceOracle (DELETE), InvariantSolvency
  - Create `scripts/check-test-mapping.sh`:
    - List Phase 0 Endure test files at branch base (`git show $(git merge-base HEAD main):packages/contracts/test/endure/` recursively)
    - List current Endure test files
    - For each path that disappeared, grep the mapping doc for that path; if not found, print the path and exit 1
    - If all disappeared paths have mapping rows, exit 0
  - Wire into `.github/workflows/ci.yml`'s `contracts-test` job as a step BEFORE `forge test`
  - Make the script idempotent (safe to run repeatedly)

  **Must NOT do**:
  - Do NOT fill in Venus replacement paths yet — T24 does the final reconciliation
  - Do NOT skip the script — CI enforcement is mandatory per spec line 618
  - Do NOT use Bash arrays in non-portable ways (script must work in CI's `ubuntu-latest` bash)

  **Recommended Agent Profile**:
  - **Category**: `quick` — Doc + script + CI yaml edit
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — within Wave 3 with T14–T23
  - **Parallel Group**: Wave 3 (with T14–T23)
  - **Blocks**: T24 (final reconciliation needs the doc + script in place)
  - **Blocked By**: T12

  **References**:

  **Pattern References**:
  - `scripts/check-forbidden-patterns.sh` — script structure pattern (bash with grep + exit codes)
  - `.github/workflows/ci.yml` — `contracts-test` job structure

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:608-620` — mandatory mapping table format

  **WHY Each Reference Matters**:
  - Spec is explicit that CI MUST enforce; missing this lets behavioral regressions slip silently

  **Acceptance Criteria**:
  - [ ] `docs/briefs/phase-0.5-venus-rebase-test-mapping.md` exists with the required table header
  - [ ] `scripts/check-test-mapping.sh` exists and is executable
  - [ ] Running the script with no deletions yet exits 0
  - [ ] Simulating a Phase 0 deletion without a mapping row exits 1
  - [ ] CI yaml runs the script in `contracts-test` job

  **QA Scenarios**:

  ```
  Scenario: Mapping check script enforces deletions
    Tool: Bash
    Preconditions: T13 implementation done
    Steps:
      1. Run: bash scripts/check-test-mapping.sh 2>&1 | tee .sisyphus/evidence/task-13-check-empty.log
      2. Assert: exit 0 (no deletions yet)
      3. Simulate: rm a phase 0 test, run script, assert exit 1
      4. Restore the file
    Expected Result: Script enforces 1:1 deletion-to-mapping
    Failure Indicators: Script passes when it shouldn't, or fails when no deletions occurred
    Evidence: .sisyphus/evidence/task-13-check-empty.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-13-check-empty.log`

  **Commit**: YES
  - Message: `chore(test): add behavior-mapping table + ci enforcement`
  - Files: `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`, `scripts/check-test-mapping.sh`, `.github/workflows/ci.yml`
  - Pre-commit: simulated-deletion test passes

- [x] 14. **Port `test/endure/integration/AliceLifecycle.t.sol` to Venus**

  **What to do**:
  - Rewrite `packages/contracts/test/endure/integration/AliceLifecycle.t.sol`
  - Use new `EndureDeployHelperVenus` (T9–T11) for setUp (T46 renames it back to `EndureDeployHelper` later)
  - Test sequence: Alice mints mock alpha → approves vAlpha30 → calls `enterMarkets([vAlpha30])` → supplies (`vAlpha30.mint(amount)`) → borrows WTAO via `vWTAO.borrow(amount)` → repays via `vWTAO.repayBorrow(amount)` → redeems via `vAlpha30.redeem(vTokens)`
  - Assert each step's effect on `Comptroller.markets`, account liquidity, balances
  - Assert WTAO is the only borrowable asset (alpha borrow attempts revert/return non-zero per Venus borrowGuard)
  - Update behavior-mapping table (T13's doc): row for the Phase 0 test mapped to this rewrite

  **Must NOT do**:
  - Do NOT borrow alpha (alpha is collateral-only per locked architecture)
  - Do NOT use Phase 0 `MToken` calls — strictly `VToken` API
  - Do NOT use `vm.expectRevert` for Compound soft-fail returns — assert return code

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — Behavior-preserving port with semantic shifts
  - **Skills**: `[test-driven-development]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent of T15–T23
  - **Parallel Group**: Wave 3 (with T15–T23)
  - **Blocks**: T24 (mapping reconciliation)
  - **Blocked By**: T12, T13

  **References**:

  **Pattern References**:
  - `packages/contracts/test/endure/integration/AliceLifecycle.t.sol` (Phase 0 Moonwell version) — behaviors to preserve
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol::test_FullLifecycleSupplyBorrowRepayRedeem` — Venus lifecycle pattern

  **API/Type References**:
  - `src/venus-staging/Tokens/VTokens/VBep20.sol` — `mint`, `borrow`, `repayBorrow`, `redeem`
  - `src/venus-staging/Comptroller/Diamond/facets/MarketFacet.sol::enterMarkets`

  **External References**:
  - Spec line 614: behavior-mapping example for AliceLifecycle

  **WHY Each Reference Matters**:
  - Spike's lifecycle test is a working Venus reference; reuse its actor pattern

  **Acceptance Criteria**:
  - [ ] `forge test --match-path test/endure/integration/AliceLifecycle.t.sol -vvv` exits 0
  - [ ] Behavior-mapping table has a row for AliceLifecycle's behavior
  - [ ] Test asserts at least: supply succeeded (balance change), borrow succeeded (debt > 0), repay reduced debt to 0, redeem returned underlying

  **QA Scenarios**:

  ```
  Scenario: AliceLifecycle GREEN against Venus chassis
    Tool: Bash
    Preconditions: T11, T13 done
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/integration/AliceLifecycle.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-14-lifecycle.log
      2. Run: grep "AliceLifecycle" docs/briefs/phase-0.5-venus-rebase-test-mapping.md | tee .sisyphus/evidence/task-14-mapping.log
    Expected Result: Test passes; mapping row present
    Failure Indicators: Any phase fails (mint, enterMarkets, borrow, repay, redeem); mapping row missing
    Evidence: .sisyphus/evidence/task-14-{lifecycle,mapping}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-14-lifecycle.log`
  - [ ] `.sisyphus/evidence/task-14-mapping.log`

  **Commit**: YES
  - Message: `test(endure): port AliceLifecycle to venus`
  - Files: `packages/contracts/test/endure/integration/AliceLifecycle.t.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
  - Pre-commit: lifecycle test exits 0

- [x] 15. **Port `test/endure/integration/Liquidation.t.sol` to Venus (price-drop + negatives)**

  **What to do**:
  - Rewrite `packages/contracts/test/endure/integration/Liquidation.t.sol`
  - Test 1: `test_PriceDropMakesAccountLiquidatable` — Alice supplies alpha, borrows WTAO, oracle drops alpha price below LT threshold, Bob calls `vWTAO.liquidateBorrow(alice, repayAmount, vAlpha30)`, assert seized vAlpha30 transferred to Bob
  - Test 2: `test_HealthyAccountNotLiquidatable` — same setup but no price drop; liquidate call returns non-zero error code
  - Test 3: `test_LiquidationUsesLTNotCF` — set CF=0.25, LT=0.35; price drops to between 0.65 (1-LT) and 0.75 (1-CF) of original — account is borrow-allowed (CF) but liquidatable (LT); assert liquidation succeeds
  - Test 4: `test_LiquidationIncentiveAppliesCorrectly` — verify seized amount = repayAmount * incentive / price ratio
  - Add mapping row

  **Must NOT do**:
  - Do NOT use external Liquidator (direct vToken liquidation only per spec)
  - Do NOT use `vm.expectRevert` for `liquidateBorrow` failure — Compound soft-fail returns
  - Do NOT skip the LT-vs-CF separation test (this is the headline behavior change of the rebase)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — Multiple scenarios, semantic precision
  - **Skills**: `[test-driven-development]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent of T14, T16–T23
  - **Parallel Group**: Wave 3
  - **Blocks**: T24
  - **Blocked By**: T12, T13

  **References**:

  **Pattern References**:
  - `packages/contracts/test/endure/integration/Liquidation.t.sol` (Phase 0 Moonwell version)
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol::test_DirectVTokenLiquidationWorksWhenLiquidatorContractUnset` — direct liquidation pattern

  **API/Type References**:
  - `src/venus-staging/Tokens/VTokens/VBep20.sol::liquidateBorrow(address borrower, uint256 repayAmount, VTokenInterface vTokenCollateral)`
  - `src/venus-staging/Comptroller/Diamond/facets/PolicyFacet.sol::liquidateBorrowAllowed`
  - `src/endure/MockResilientOracle.sol::setUnderlyingPrice` — price manipulation hook

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:48-50` — finding F2 (4-arg liquidateCalculateSeizeTokens)
  - Decision #8: CF=0.25, LT=0.35 — 10% gap exists for exactly this test

  **WHY Each Reference Matters**:
  - The 10% CF/LT gap (Decision #8) is the proof surface for distinguishing the two thresholds
  - Direct liquidation is the only path Endure exposes; external Liquidator deployments would fail

  **Acceptance Criteria**:
  - [ ] All 4 liquidation tests pass
  - [ ] `test_LiquidationUsesLTNotCF` explicitly asserts behavior in the gap region
  - [ ] Mapping row present

  **QA Scenarios**:

  ```
  Scenario: All liquidation scenarios pass
    Tool: Bash
    Preconditions: T11, T13 done
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/integration/Liquidation.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-15-liq.log
      2. Assert: 4 tests pass
    Expected Result: 4/4 pass
    Failure Indicators: Any test fails; LT-vs-CF test missing or skipped
    Evidence: .sisyphus/evidence/task-15-liq.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-15-liq.log`

  **Commit**: YES
  - Message: `test(endure): port Liquidation to venus + LT/CF separation`
  - Files: `packages/contracts/test/endure/integration/Liquidation.t.sol`, mapping doc
  - Pre-commit: 4 tests pass

- [x] 16. **Port `test/endure/SeedDeposit.t.sol` for vTokens**

  **What to do**:
  - Rewrite `packages/contracts/test/endure/SeedDeposit.t.sol`
  - Assert: each vToken (`vWTAO`, `vAlpha30`, `vAlpha64`) has `totalSupply() >= 1e18` immediately after deploy
  - Assert: each vToken has `balanceOf(0xdEaD) > 0` (seed was burned)
  - Assert: no other account has vTokens at this point
  - Add mapping row

  **Must NOT do**:
  - Do NOT seed Alpha markets with WTAO (each market seeded with its own underlying)
  - Do NOT skip burn step (Phase 0 invariant)

  **Recommended Agent Profile**:
  - **Category**: `quick` — Simple state assertion port
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3
  - **Blocks**: T24
  - **Blocked By**: T12, T13

  **References**:

  **Pattern References**:
  - `packages/contracts/test/endure/SeedDeposit.t.sol` (Phase 0 Moonwell version) — behavior to preserve

  **WHY Each Reference Matters**:
  - Phase 0 invariant: every market starts non-empty to prevent first-depositor exploits

  **Acceptance Criteria**:
  - [ ] `forge test --match-path test/endure/SeedDeposit.t.sol` passes
  - [ ] Mapping row present

  **QA Scenarios**:

  ```
  Scenario: Seed-and-burn invariant holds
    Tool: Bash
    Preconditions: T11 done
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/SeedDeposit.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-16-seed.log
    Expected Result: All assertions pass
    Failure Indicators: Any market with totalSupply < 1e18 or balanceOf(0xdEaD) == 0
    Evidence: .sisyphus/evidence/task-16-seed.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-16-seed.log`

  **Commit**: YES
  - Message: `test(endure): port SeedDeposit to vtokens`

- [x] 17. **Port `test/endure/RBACSeparation.t.sol` for Venus ACM-gated roles**

  **What to do**:
  - Rewrite `packages/contracts/test/endure/RBACSeparation.t.sol`
  - Replace Moonwell guardian model (admin, pauseGuardian, borrowCapGuardian, supplyCapGuardian) with Venus ACM-gated roles
  - **REALITY CHECK** (per Momus): Endure's default `AllowAllAccessControlManager` (verified at `src/endure/AllowAllAccessControlManager.sol:36-59`) returns `true` for EVERY `isAllowedToCall(...)` check. Therefore any test asserting "unauthorized account is rejected by ACM" against the default mock will FAIL — the mock would let every account through. The test must either (a) deploy a SECOND, narrower mock for negative-path cases, OR (b) limit scope to admin-only paths that bypass ACM entirely.
  - **APPROACH (decided per Momus blocker fix)**: Author a NEW `src/endure/DenyAllAccessControlManager.sol` (Endure-authored, simple — returns `false` for every `isAllowedToCall`) and use it for negative-path tests. The default `AllowAllAccessControlManager` continues to be used by the helper for positive-path setup. Tests swap ACMs via a helper method `setAccessControlManager(address)` to flip behavior between cases.
  - Test 1 (positive): With `AllowAllAccessControlManager` wired, ANY account can call `_setMarketBorrowCaps([...], [...])` and it succeeds. Confirms the production ACM-gating path works end-to-end (real production would substitute a configurable ACM with explicit role grants).
  - Test 2 (negative): Hot-swap to `DenyAllAccessControlManager` via `Comptroller(unitroller)._setAccessControl(denyAcm)`. NOW any account (including deployer) attempting `_setMarketBorrowCaps([...], [...])` is REJECTED by ACM (call reverts with ACM's denial OR returns non-zero error code per Venus's `ensureAllowed` pattern). Confirms the ACM gate is actually enforced.
  - Test 3 (admin-only paths bypass ACM): deployer/admin can still call `_setPendingImplementation` and `_acceptImplementation` regardless of ACM (these are gated on `msg.sender == admin`, NOT ACM). Verify a non-deployer account is rejected on these.
  - Document in test docstrings that production deployment would use a real ACM (e.g., `AccessControlManager` from `@venusprotocol/governance-contracts`) with explicit role grants per role-string per address.
  - Add mapping row

  **Must NOT do**:
  - Do NOT use Moonwell `Comptroller(unitroller).pauseGuardian()` API (doesn't exist on Venus)
  - Do NOT assert ACM rejection while `AllowAllAccessControlManager` is wired — the mock allows everything; the test would always fail
  - Do NOT skip the `DenyAllAccessControlManager` mock — without it, negative-path coverage is impossible
  - Do NOT modify the default `AllowAllAccessControlManager` behavior (Stance B-style isolation; new behavior goes in a new file)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — Semantic redesign per chassis change
  - **Skills**: `[test-driven-development]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3
  - **Blocks**: T24
  - **Blocked By**: T12, T13

  **References**:

  **Pattern References**:
  - `packages/contracts/test/endure/RBACSeparation.t.sol` (Phase 0 Moonwell version) — behaviors to map to Venus equivalents
  - `src/endure/AllowAllAccessControlManager.sol:36-59::isAllowedToCall` — verified: returns `true` always (allow-all, cannot serve negative-path tests)

  **NEW FILE TO AUTHOR**:
  - `packages/contracts/src/endure/DenyAllAccessControlManager.sol` — implements `IAccessControlManagerV8` returning `false` for every `isAllowedToCall(...)`. Mirror the `AllowAllAccessControlManager` shape but flip the booleans. ~50 LOC.

  **API/Type References**:
  - `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol::_setAccessControl(address)` — admin-only setter to swap the ACM at runtime
  - `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol` — ACM-gated setters use `ensureAllowed("functionSig")`; reject path returns Compound soft-fail (verified: most ACM-gated functions revert with `Unauthorized` rather than soft-fail — confirm during test authoring)

  **External References**:
  - Spec line 630: required preserved behavior for RBAC separation

  **WHY Each Reference Matters**:
  - Venus uses fundamentally different access model from Moonwell guardians; tests must shift accordingly

  **Acceptance Criteria**:
  - [ ] `src/endure/DenyAllAccessControlManager.sol` exists (NEW Endure-authored mock; ~50 LOC; mirrors AllowAll but returns false)
  - [ ] All 3 tests pass: positive (allow-all permits), negative (deny-all rejects), admin-bypass (admin paths bypass ACM)
  - [ ] Test 2 (negative) explicitly hot-swaps ACM via `_setAccessControl(denyAcm)` and asserts the subsequent setter call is rejected
  - [ ] Test 3 (admin-bypass) asserts a non-admin account is rejected on `_setPendingImplementation` regardless of ACM state
  - [ ] Mapping row present
  - [ ] Test docstrings document that production deployment would use a real configurable ACM with explicit per-function role grants

  **QA Scenarios**:

  ```
  Scenario: ACM positive + negative + admin-bypass paths verified
    Tool: Bash
    Preconditions: T11, T13 done; DenyAllAccessControlManager.sol authored
    Steps:
      1. Run: ls packages/contracts/src/endure/DenyAllAccessControlManager.sol | tee .sisyphus/evidence/task-17-deny-mock.log
      2. Run: forge test --root packages/contracts --match-path test/endure/RBACSeparation.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-17-rbac.log
      3. Assert: deny mock exists; 3 tests pass (positive permits, negative rejects, admin-bypass)
    Expected Result: All 3 RBAC scenarios pass; ACM gate is verifiably enforced via the deny-mock swap
    Failure Indicators: deny mock missing; allow-all mock used for negative path (test will be unreliable); admin-bypass test missing
    Evidence: .sisyphus/evidence/task-17-{deny-mock,rbac}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-17-rbac.log`

  **Commit**: YES
  - Message: `test(endure): port RBACSeparation to venus ACM model + add DenyAll mock`
  - Files: `packages/contracts/test/endure/RBACSeparation.t.sol`, `packages/contracts/src/endure/DenyAllAccessControlManager.sol` (NEW), `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`

- [x] 18. **Port `EnduRateModelParams.t.sol` + `MockAlpha.t.sol` + `WTAO.t.sol`**

  **What to do**:
  - `EnduRateModelParams.t.sol`: verify TwoKinksInterestRateModel is constructed with the Endure parameters from `src/endure/EnduRateModelParams.sol`. Re-derive any Moonwell-specific assertions for Venus's `TwoKinksInterestRateModel` API.
  - `MockAlpha.t.sol`: still tests the mock ERC20 (`MockAlpha30`, `MockAlpha64`); should require minimal change — only update setUp to use new helper if it deploys via helper at all
  - `WTAO.t.sol`: same — `WTAO` mock is unchanged; verify it still passes with no modifications, or trivial modifications
  - Add mapping rows for all three

  **Must NOT do**:
  - Do NOT redesign EnduRateModelParams — IRM constants are stable across rebase
  - Do NOT delete these tests — all 3 are still relevant in Venus chassis

  **Recommended Agent Profile**:
  - **Category**: `quick` — Small adaptations, no semantic shift
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3
  - **Blocks**: T24
  - **Blocked By**: T12, T13

  **References**:

  **Pattern References**:
  - Existing files: `test/endure/{EnduRateModelParams,MockAlpha,WTAO}.t.sol`
  - `src/venus-staging/InterestRateModels/TwoKinksInterestRateModel.sol` — IRM API

  **API/Type References**:
  - `TwoKinksInterestRateModel` constructor params (compare to Phase 0 Moonwell IRM constructor)

  **WHY Each Reference Matters**:
  - Phase 0 IRM tests asserted Moonwell-specific values — Venus's TwoKinks may have different return semantics for the same blended rate

  **Acceptance Criteria**:
  - [ ] All 3 tests pass against new helper
  - [ ] 3 mapping rows present (or each marked "no behavior change" if appropriate)

  **QA Scenarios**:

  ```
  Scenario: Three small ports all green
    Tool: Bash
    Preconditions: T11, T13 done
    Steps:
      1. Run: forge test --root packages/contracts --match-path "test/endure/{EnduRateModelParams,MockAlpha,WTAO}.t.sol" -vvv 2>&1 | tee .sisyphus/evidence/task-18-three.log
    Expected Result: All 3 test files pass
    Failure Indicators: Any failure
    Evidence: .sisyphus/evidence/task-18-three.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-18-three.log`

  **Commit**: YES
  - Message: `test(endure): port IRM params + mock alpha + wtao tests`

- [x] 19. **Port `test/endure/invariant/InvariantSolvency.t.sol` + `handlers/EndureHandler.sol` (1000×50)**

  **What to do**:
  - Rewrite `InvariantSolvency.t.sol` to use the new `EndureDeployHelperVenus` (renamed back to `EndureDeployHelper` in T46)
  - Rewrite `handlers/EndureHandler.sol` to use Venus VToken API (mint, borrow, repay, redeem, liquidateBorrow direct) instead of Moonwell MToken API
  - Preserve the solvency invariant: `sum(supplies) - sum(borrows) >= protocolReserves` (or whatever Phase 0 expressed; map exactly into Venus equivalents)
  - Run with full Phase 0 thresholds: 1000 runs × 50 depth (already configured in `foundry.toml`)
  - Add mapping row

  **Must NOT do**:
  - Do NOT lower the invariant runs/depth (configured 1000×50)
  - Do NOT call functions that don't exist on Venus (e.g., Moonwell's reward distribution paths)

  **Recommended Agent Profile**:
  - **Category**: `deep` — Invariant design + handler rewrite require semantic care
  - **Skills**: `[test-driven-development]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent within Wave 3
  - **Parallel Group**: Wave 3
  - **Blocks**: T24
  - **Blocked By**: T12, T13

  **References**:

  **Pattern References**:
  - `packages/contracts/test/endure/invariant/InvariantSolvency.t.sol` (Phase 0 version)
  - `packages/contracts/test/endure/invariant/handlers/EndureHandler.sol` (Phase 0 version)

  **API/Type References**:
  - `src/venus-staging/Tokens/VTokens/VBep20.sol` — full borrower-facing API
  - `src/venus-staging/Comptroller/Diamond/facets/MarketFacet.sol::enterMarkets`, `exitMarket`
  - `forge-std/StdInvariant.sol` — `targetContract`, `targetSelector`

  **External References**:
  - Spec line 629: required preserved behavior — solvency invariant under handler actions

  **WHY Each Reference Matters**:
  - Invariant testing catches reentrancy + accounting bugs; lowering runs/depth weakens the safety net

  **Acceptance Criteria**:
  - [ ] `forge test --match-path test/endure/invariant/InvariantSolvency.t.sol --invariant-runs 1000 --invariant-depth 50` exits 0
  - [ ] No invariant violation reported
  - [ ] Mapping row present

  **QA Scenarios**:

  ```
  Scenario: Solvency invariant holds at full Phase 0 thresholds
    Tool: Bash
    Preconditions: T11, T13 done; foundry.toml retains 1000×50
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/invariant/InvariantSolvency.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-19-invariant.log
      2. Assert: log shows runs ≥ 1000, depth ≥ 50, no violation
    Expected Result: Invariant holds
    Failure Indicators: Any "invariant violated" message; runs/depth lowered
    Evidence: .sisyphus/evidence/task-19-invariant.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-19-invariant.log`

  **Commit**: YES
  - Message: `test(endure): port solvency invariant + handler to venus`

- [x] 20. **Net-new `test/endure/venus/LiquidationThreshold.t.sol` (LT vs CF separation)**

  **What to do**:
  - New test file proving CF gates borrow eligibility (`borrowAllowed`) and LT gates liquidation eligibility (`liquidateBorrowAllowed`) DISTINCTLY
  - Setup: vAlpha30 with CF=0.25e18, LT=0.35e18; Alice supplies 100 alpha, oracle says 1 alpha = 1 USD
  - Test 1: `test_BorrowEligibilityUsesCF` — Alice can borrow up to 25 USD-equivalent of WTAO (CF * collateral); the 26th USD borrow is rejected
  - Test 2: `test_LiquidationEligibilityUsesLT` — Alice borrows 25 USD; price drops alpha to 0.7 USD; Alice's debt-to-collateral ratio crosses LT (35%) but not yet bankruptcy; liquidation succeeds
  - Test 3: `test_GapBetweenCFAndLT` — Alice borrows max under CF; price drops to put her between CF threshold and LT threshold; she is borrow-bound (cannot borrow more) but NOT liquidatable yet
  - Add to mapping doc as net-new (no Phase 0 row needed)

  **Must NOT do**:
  - Do NOT use a CF/LT gap less than 10% (Decision #8 default is 10%; tests need clean signal)
  - Do NOT use external Liquidator
  - Do NOT skip Test 3 (the gap test is the headline proof of the rebase value)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — Semantic precision around new behavior
  - **Skills**: `[test-driven-development]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3
  - **Blocks**: T24 (mapping doc reconciliation)
  - **Blocked By**: T12, T13

  **References**:

  **Pattern References**:
  - `test/endure/integration/Liquidation.t.sol` (T15) — liquidation actor pattern

  **API/Type References**:
  - `src/venus-staging/Comptroller/Diamond/facets/PolicyFacet.sol::borrowAllowed`, `liquidateBorrowAllowed`
  - `src/venus-staging/Comptroller/Diamond/facets/PolicyFacet.sol::getAccountLiquidity` (LT-aware liquidity for liquidation eligibility)
  - `src/venus-staging/Lens/ComptrollerLens.sol::getHypotheticalAccountLiquidity` (CF-aware hypothetical liquidity)

  **External References**:
  - Spec line 632: net-new behaviors

  **WHY Each Reference Matters**:
  - This test PROVES the rebase value proposition (separate CF/LT). Without it, the rebase has no observable benefit over Phase 0 Moonwell.

  **Acceptance Criteria**:
  - [ ] All 3 sub-tests pass
  - [ ] Test docstrings explain the CF/LT semantic clearly

  **QA Scenarios**:

  ```
  Scenario: LT vs CF separation proven
    Tool: Bash
    Preconditions: T11, T13 done
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/venus/LiquidationThreshold.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-20-lt.log
    Expected Result: 3/3 pass
    Failure Indicators: Any test fails; gap test missing
    Evidence: .sisyphus/evidence/task-20-lt.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-20-lt.log`

  **Commit**: YES
  - Message: `test(venus): prove CF/LT separation`

- [x] 21. **Net-new `test/endure/venus/CollateralFactorOrdering.t.sol` (oracle-unset rejection + LT<CF rejection)**

  **What to do**:
  - New test file proving Venus's CF/LT setting ordering constraints
  - Test 1: `test_SetCFRejectsWhenOracleUnset` — deploy chassis WITHOUT setting oracle prices, attempt `setCollateralFactor(vAlpha, 0.25e18, 0.35e18)` (NO leading underscore — Venus naming, verified at `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol:217,248`), assert non-zero return code (Compound soft-fail)
  - Test 2: `test_SetCFRejectsLTBelowCF` — set oracle, attempt `setCollateralFactor(vAlpha, 0.4e18, 0.3e18)` with LT<CF, assert non-zero return code
  - Test 3: `test_SetCFAcceptsValidParams` — set oracle, valid CF=0.25, LT=0.35 → return 0, state updated
  - Add to mapping doc as net-new

  **Must NOT do**:
  - Do NOT use `vm.expectRevert` (return code, not revert)
  - Do NOT modify the helper to remove the ordering — these tests deploy chassis manually for the rejection scenarios

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — Tests against soft-fail semantics
  - **Skills**: `[test-driven-development]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3
  - **Blocks**: T24
  - **Blocked By**: T12, T13

  **References**:

  **API/Type References**:
  - `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol:217,248::setCollateralFactor` (NO leading underscore) — TWO overloads exist; both return `uint`

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:53-54` — finding F3
  - Spec line 633: net-new behaviors (oracle ordering, LT<CF)

  **WHY Each Reference Matters**:
  - These are the deploy-helper guard rails proven; without them, deploy could silently corrupt market state

  **Acceptance Criteria**:
  - [ ] 3/3 tests pass
  - [ ] Test 1 + 2 assert specific Compound error codes (or at least non-zero)

  **QA Scenarios**:

  ```
  Scenario: CF/LT ordering invariants hold
    Tool: Bash
    Preconditions: T11, T13 done
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/venus/CollateralFactorOrdering.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-21-cf-order.log
    Expected Result: 3/3 pass
    Failure Indicators: Any test fails; revert assertions used instead of return-code
    Evidence: .sisyphus/evidence/task-21-cf-order.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-21-cf-order.log`

  **Commit**: YES
  - Message: `test(venus): prove CF ordering rejections (oracle + LT<CF)`

- [x] 22. **Net-new `test/endure/venus/BorrowCapSemantics.t.sol` (cap=0 disables)**

  **What to do**:
  - New test file proving Venus's `borrowCap == 0` DISABLES borrowing (semantic flip from Moonwell where 0 == unlimited)
  - **CRITICAL TEST ISOLATION** (per Metis review): Alpha markets have BOTH `borrowCap == 0` AND `isBorrowAllowed == false` from T11's deploy helper. To test cap semantics IN ISOLATION (so the test proves what it claims), each cap test must first set `isBorrowAllowed = true` for the test market via `Comptroller(unitroller).setIsBorrowAllowed(0, vAlphaTarget, true)` so the cap is the ONLY remaining borrow gate. Without this isolation, Test 1 would pass for the wrong reason (`isBorrowAllowed == false` rejecting before cap is even checked).
  - Test 1: `test_BorrowCapZeroDisablesBorrow` — pre-step: enable `isBorrowAllowed = true` on vAlpha30; THEN: vAlpha30 has cap 0; Alice supplies and `enterMarkets`; `vAlpha30.borrow(1)` returns non-zero error code SPECIFICALLY because of the cap (not because of `isBorrowAllowed`). Assert the failure event signature matches the cap-rejection path, NOT the isBorrowAllowed-rejection path.
  - Test 2: `test_BorrowCapMaxAllowsBorrow` — vWTAO has cap `type(uint256).max` AND `isBorrowAllowed == true` (already set in T11); borrow succeeds
  - Test 3: `test_BorrowCapNonZeroFiniteRespectsLimit` — pre-step: enable `isBorrowAllowed = true` on a test market with finite cap; set cap to 100 ether; borrow 99 succeeds, 101 rejected (cap-rejection path)
  - Add to mapping doc as net-new

  **Must NOT do**:
  - Do NOT use Moonwell's borrow-cap semantic (0 = unlimited) — that semantic is GONE
  - Do NOT skip Test 3 (verifies Venus respects finite cap correctly)

  **Recommended Agent Profile**:
  - **Category**: `quick` — Simple borrow-attempt + assert pattern
  - **Skills**: `[test-driven-development]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3
  - **Blocks**: T24
  - **Blocked By**: T12, T13

  **References**:

  **API/Type References**:
  - `src/venus-staging/Comptroller/Diamond/facets/PolicyFacet.sol::borrowAllowed` — checks borrowCap
  - `src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol::_setMarketBorrowCaps`

  **External References**:
  - Spec line 633: net-new behaviors (cap=0 disables)
  - Spec risk register line 746: borrow cap semantic flip

  **WHY Each Reference Matters**:
  - Silent semantic flip is the highest-risk Venus change; explicit test prevents future regression

  **Acceptance Criteria**:
  - [ ] 3/3 tests pass

  **QA Scenarios**:

  ```
  Scenario: Borrow cap semantics verified
    Tool: Bash
    Preconditions: T11, T13 done
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/venus/BorrowCapSemantics.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-22-cap.log
    Expected Result: 3/3 pass
    Failure Indicators: cap=0 allows borrow (regression to Moonwell semantic)
    Evidence: .sisyphus/evidence/task-22-cap.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-22-cap.log`

  **Commit**: YES
  - Message: `test(venus): prove borrowCap=0 disables borrowing`

- [x] 22b. **Net-new `test/endure/venus/RewardFacetEnable.t.sol` — prove rewards are usable when admin enables them**

  **What to do**:
  - Per user clarification, RewardFacet must be "fully functional, deployable, and usable if desired." This task proves the usable-if-desired path end-to-end.
  - Create `packages/contracts/test/endure/venus/RewardFacetEnable.t.sol`
  - Setup: standard Venus deploy via `EndureDeployHelperVenus`. Deploy a mock `XVS` token under `src/endure/MockXVS.sol` (a simple OZ ERC20 mintable; this is Endure-authored test infrastructure, NOT a vendored Venus deployment). Mint a supply of mock XVS to the deployer.
  - **PRECONDITION** (depends on T8/T9 expanded selector cut): Verify the diamond cut registers ALL of:
    - `venusSupplySpeeds(address)` on MarketFacet (auto-getter from `ComptrollerStorage.sol:234`)
    - `venusBorrowSpeeds(address)` on MarketFacet (auto-getter from `ComptrollerStorage.sol:231`)
    - `_setXVSToken(address)` on SetterFacet (verified at `SetterFacet.sol:604`)
    - `_setVenusSpeeds(VToken[],uint256[],uint256[])` on PolicyFacet (verified at `PolicyFacet.sol:477`)
    - `getXVSAddress()` on RewardFacet (sourced from FacetBase, verified at `FacetBase.sol:234`)
    - `claimVenus(address)` on RewardFacet (already in spike)
    - `_grantXVS(address,uint256)` on RewardFacet (verified at `RewardFacet.sol:129`)
    Without ALL 7 of these in the cut, this task cannot complete (helper.enableVenusRewards or test assertions revert).
  - Test 1: `test_RewardSpeedsZeroByDefault` — assert `Comptroller(unitroller).venusSupplySpeeds(vWTAO) == 0` and `venusBorrowSpeeds(vWTAO) == 0` immediately after `deployAll()` (no rewards by default)
  - Test 2: `test_AdminCanEnableRewards` — setup: `mockXvs.mint(deployer, 100_000e18); mockXvs.approve(address(helper), 100_000e18);` then admin calls `helper.enableVenusRewards(mockXvs, [vWTAO, vAlpha30, vAlpha64], [1e15, 1e15, 1e15], [1e15, 1e15, 1e15], 100_000e18)`. Internally, the helper performs 3 steps: (a) `_setXVSToken(mockXvs)` via SetterFacet, (b) `transferFrom(deployer, unitroller, 100_000e18)` to fund the comptroller, (c) `_setVenusSpeeds(...)` via PolicyFacet. Asserts:
    - `mockXvs.balanceOf(address(unitroller)) == 100_000e18` (funding step succeeded — required for Test 3's claim to actually transfer)
    - `Comptroller(unitroller).getXVSAddress() == mockXvs` (XVS ERC20 address registration — uses the FacetBase getter at `FacetBase.sol:234` registered on RewardFacet per T8). DO NOT use `getXVSVTokenAddress()` here — that returns the vToken-XVS market, NOT the ERC20 (different concept; see T8's disambiguation note).
    - `Comptroller(unitroller).venusSupplySpeeds(vWTAO) > 0` and similar for vAlpha30, vAlpha64 (speeds set non-zero)
  - Test 3: `test_RewardsAccrueOnSupplyAndBorrow` — Alice supplies alpha + borrows WTAO; advance blocks (`vm.roll(block.number + 100)`); call `Comptroller(unitroller).claimVenus(alice)`; assert Alice's mock XVS balance increased
  - Test 4: `test_RewardsRevertWhenXVSContractMissing` — call `enableVenusRewards(address(0), [vWTAO], [1e15], [1e15], 0)` → assert revert. Verified at `SetterFacet.sol:606` — `_setXVSToken` calls `ensureNonzeroAddress(xvs_)` which reverts on zero address. The helper calls `_setXVSToken` BEFORE the funding step, so revert fires before any transfer is attempted.
  - Add to behavior-mapping doc as net-new (no Phase 0 row needed; this is rewards functionality Phase 0 didn't have)

  **Must NOT do**:
  - Do NOT use real XVS contract from `src/venus-staging/Tokens/XVS/XVS.sol` (that's the real Venus token; we use a simpler mock under `src/endure/`)
  - Do NOT add `enableVenusRewards` to the default `deployAll()` flow (rewards stay opt-in)
  - Do NOT hardcode reward speeds in the helper (they must be parameters)
  - Do NOT skip Test 3 (rewards must actually accrue and be claimable end-to-end, not just configurable)
  - **CARVE-OUT NOTE**: This task INTENTIONALLY expands Endure's deployed surface with `src/endure/MockXVS.sol` and `test/endure/venus/RewardFacetEnable.t.sol`. T30/T31/T32/T33 isolation greps are explicitly modified to permit these two files. The carve-out is documented in FORK_MANIFEST.md and the plan's "Documented Deviations from Spec" section.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — Multi-step reward-distribution test with cross-block accrual
  - **Skills**: `[test-driven-development]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent of T14–T22, T23
  - **Parallel Group**: Wave 3 (with T14–T23)
  - **Blocks**: T24 (mapping doc reconciliation)
  - **Blocked By**: T11 (helper Phase 3 must expose `enableVenusRewards`), T13 (mapping table)

  **References**:

  **Pattern References**:
  - `packages/contracts/src/venus-staging/Comptroller/Diamond/facets/RewardFacet.sol:33,42,55,63,129,143,178,220,254` — full reward-distribution surface
  - `packages/contracts/src/venus-staging/Comptroller/Diamond/facets/PolicyFacet.sol:477::_setVenusSpeeds(VToken[],uint256[],uint256[])` — reward-speed admin setter (verified location: PolicyFacet, NOT SetterFacet — earlier draft was wrong)
  - `packages/contracts/src/venus-staging/Comptroller/Diamond/facets/SetterFacet.sol:604::_setXVSToken(address)` — XVS ERC20 admin setter (required to register MockXVS via diamond)
  - `packages/contracts/src/venus-staging/Comptroller/Diamond/facets/FacetBase.sol:234::getXVSAddress()` — XVS ERC20 getter (lives on FacetBase; selector registered on RewardFacet by convention since RewardFacet inherits FacetBase via XVSRewardsHelper)

  **API/Type References**:
  - `RewardFacet.sol:33::claimVenus(address holder)` — claim entry point
  - `RewardFacet.sol:129::_grantXVS(address recipient, uint256 amount)` — XVS grant path
  - `RewardFacet.sol:254::getXVSVTokenAddress()` — XVS contract registration query
  - OpenZeppelin `ERC20.sol` — for `MockXVS` simple implementation

  **External References**:
  - User clarification (post-Round-4): "RewardFacet should be optional, but also fully functional, deployable and usable if desired"
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:147` — Decision #10 (RewardFacet wired with zero state)

  **WHY Each Reference Matters**:
  - Without this test, "wired but functional" is unverified — RewardFacet could compile and register selectors yet still revert at runtime when actually used
  - Test 3 (cross-block accrual) is the only way to prove the reward math actually executes, not just that setters succeed

  **Acceptance Criteria**:
  - [ ] File `test/endure/venus/RewardFacetEnable.t.sol` exists with 4 tests
  - [ ] `src/endure/MockXVS.sol` exists (simple OZ ERC20)
  - [ ] T8/T9 cut includes ALL 7 prerequisite selectors (`venusSupplySpeeds(address)`, `venusBorrowSpeeds(address)`, `_setXVSToken`, `_setVenusSpeeds`, `getXVSAddress`, `claimVenus(address)`, `_grantXVS(address,uint256)`); pre-flight: `Diamond(payable(unitroller)).facetAddress(<each selector>) != address(0)` for all 7
  - [ ] `forge test --match-path test/endure/venus/RewardFacetEnable.t.sol -vvv` exits 0; all 4 tests pass
  - [ ] Test 2 asserts `getXVSAddress() == mockXvs` (NOT `getXVSVTokenAddress`)
  - [ ] Test 3 assertion: `mockXvs.balanceOf(alice) > 0` after `claimVenus`
  - [ ] Behavior-mapping doc has a net-new row for this test
  - [ ] Default `EndureDeployHelperVenus.deployAll()` STILL leaves reward speeds at zero (T7 Deploy.t.sol still asserts this)

  **QA Scenarios**:

  ```
  Scenario: Reward enable path works end-to-end
    Tool: Bash
    Preconditions: T11 done with enableVenusRewards exposed; T13 done; src/endure/MockXVS.sol authored
    Steps:
      1. Run: forge build --root packages/contracts 2>&1 | tee .sisyphus/evidence/task-22b-build.log
      2. Run: forge test --root packages/contracts --match-path test/endure/venus/RewardFacetEnable.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-22b-tests.log
      3. Assert: build clean; 4/4 tests pass; log shows Alice's XVS balance increment
    Expected Result: All 4 reward tests pass; rewards demonstrably claimable
    Failure Indicators: Helper enableVenusRewards missing; reward accrual returns zero (math bug); claim reverts
    Evidence: .sisyphus/evidence/task-22b-{build,tests}.log

  Scenario: Default deploy still has zero reward speeds (regression check)
    Tool: Bash
    Preconditions: T22b implementation done
    Steps:
      1. Run: forge test --root packages/contracts --match-path test/endure/venus/Deploy.t.sol -vvv 2>&1 | tail -20 | tee .sisyphus/evidence/task-22b-deploy-regression.log
      2. Assert: T7 Deploy.t.sol still passes; reward-speed assertions (if T7 added them) still show zero post-deploy
    Expected Result: Default deploy unchanged; rewards opt-in only
    Failure Indicators: Default deploy now sets non-zero speeds (broke "optional" invariant)
    Evidence: .sisyphus/evidence/task-22b-deploy-regression.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-22b-build.log`
  - [ ] `.sisyphus/evidence/task-22b-tests.log`
  - [ ] `.sisyphus/evidence/task-22b-deploy-regression.log`

  **Commit**: YES
  - Message: `test(venus): prove RewardFacet rewards path is fully usable when enabled`
  - Files: `packages/contracts/test/endure/venus/RewardFacetEnable.t.sol`, `packages/contracts/src/endure/MockXVS.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
  - Pre-commit: 4 tests pass; default deploy regression test still green

- [x] 23. **Rename Stage A spike → `test/endure/venus/Lifecycle.t.sol`; delete redundant scenarios**

  **What to do**:
  - `git mv packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol packages/contracts/test/endure/venus/Lifecycle.t.sol`
  - Refactor file: remove `_buildFacetCut` and selector helpers (now lives in EndureDeployHelperVenus from T9); replace inline setUp with `helper = new EndureDeployHelperVenus(); helper.deployAll()` (T46 renames back to `EndureDeployHelper`)
  - Keep the 7 spike tests as-is (they validate end-to-end behavior; redundancy with T14/T15 is acceptable as integration coverage)
  - Update mapping doc: spike tests have a "preserved as Lifecycle.t.sol" row

  **Must NOT do**:
  - Do NOT delete any of the 7 spike tests (they cover gates that complement T14/T15)
  - Do NOT keep the inline `_buildFacetCut` (DRY — it's in helper now)

  **Recommended Agent Profile**:
  - **Category**: `quick` — Mechanical rename + cleanup
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent of T14–T22
  - **Parallel Group**: Wave 3
  - **Blocks**: T24
  - **Blocked By**: T11

  **References**:

  **Pattern References**:
  - `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol` — file to rename
  - Spec finding F10: spike already at Stage-B-final location; Stage B Task 4 is no-op

  **WHY Each Reference Matters**:
  - F10 explicitly notes "fold the spike into test/endure/venus/" is a no-op since the file is already there — this task is just the rename + helper extraction

  **Acceptance Criteria**:
  - [ ] `packages/contracts/test/endure/venus/Lifecycle.t.sol` exists
  - [ ] `packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol` does NOT exist
  - [ ] All 7 tests still pass
  - [ ] No `_buildFacetCut` definition in the renamed file (extracted to helper)

  **QA Scenarios**:

  ```
  Scenario: Spike renamed and slimmed without test loss
    Tool: Bash
    Preconditions: T11 done
    Steps:
      1. Run: ls packages/contracts/test/endure/venus/Lifecycle.t.sol packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol 2>&1 | tee .sisyphus/evidence/task-23-rename.log
      2. Run: forge test --root packages/contracts --match-path test/endure/venus/Lifecycle.t.sol -vvv 2>&1 | tee .sisyphus/evidence/task-23-tests.log
      3. Assert: spike file is missing; lifecycle file exists; 7 tests pass
    Expected Result: Rename clean, tests preserved
    Failure Indicators: Both files exist (incomplete rename), test count drops below 7
    Evidence: .sisyphus/evidence/task-23-{rename,tests}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-23-rename.log`
  - [ ] `.sisyphus/evidence/task-23-tests.log`

  **Commit**: YES
  - Message: `refactor(test): rename spike to Lifecycle + extract facet cut to helper`

- [ ] 24. **Delete `test/endure/MockPriceOracle.t.sol`; finalize behavior-mapping rows for ALL deleted Phase 0 tests**

  **What to do**:
  - Delete `packages/contracts/test/endure/MockPriceOracle.t.sol` (Phase 0 oracle is replaced by `MockResilientOracle` in Chunk 5b; this test asserts Moonwell-specific oracle behavior that no longer applies)
  - Reconcile `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`: every Phase 0 test path that no longer exists must have a row
  - Run `scripts/check-test-mapping.sh` and ensure exit 0
  - Run full `forge test --root packages/contracts` — should be GREEN with all ports + new tests + spike-renamed Lifecycle
  - Add a final row counting net-new Venus tests

  **Must NOT do**:
  - Do NOT delete `src/endure/MockPriceOracle.sol` yet (Chunk 5b deletes it)
  - Do NOT delete other Phase 0 tests not explicitly slated (each deletion needs justification)

  **Recommended Agent Profile**:
  - **Category**: `quick` — Cleanup + reconciliation
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO — depends on T14–T23
  - **Parallel Group**: Wave 3 closer
  - **Blocks**: Wave 4 (Wave 3 must close green before Hardhat work begins)
  - **Blocked By**: T13, T14, T15, T16, T17, T18, T19, T20, T21, T22, T22b, T23

  **References**:

  **Pattern References**:
  - All tasks T14–T23 mapping rows
  - `scripts/check-test-mapping.sh` (T13)

  **WHY Each Reference Matters**:
  - This is the gate that proves Wave 3 (Chunk 3) is complete and CI-enforceable

  **Acceptance Criteria**:
  - [ ] `bash scripts/check-test-mapping.sh` exits 0
  - [ ] `forge test --root packages/contracts` exits 0 with strictly more tests than Phase 0 (additions: 4 net-new venus tests + Lifecycle preserved spike)
  - [ ] `test/endure/MockPriceOracle.t.sol` does NOT exist
  - [ ] `src/endure/MockPriceOracle.sol` STILL EXISTS (Chunk 5b deletes it)

  **QA Scenarios**:

  ```
  Scenario: Mapping clean, full Foundry suite green
    Tool: Bash
    Preconditions: T13–T23 done
    Steps:
      1. Run: bash scripts/check-test-mapping.sh 2>&1 | tee .sisyphus/evidence/task-24-mapping.log
      2. Run: forge test --root packages/contracts 2>&1 | tail -10 | tee .sisyphus/evidence/task-24-fulltree.log
      3. Run: ls packages/contracts/test/endure/MockPriceOracle.t.sol 2>&1 | tee .sisyphus/evidence/task-24-mockoracle-deleted.log
      4. Run: ls packages/contracts/src/endure/MockPriceOracle.sol | tee .sisyphus/evidence/task-24-mockoracle-src-still-present.log
      5. Assert: mapping check exits 0, tests pass, .t.sol gone, src .sol still present
    Expected Result: Wave 3 closes green
    Failure Indicators: Mapping incomplete, test regression, premature src deletion
    Evidence: .sisyphus/evidence/task-24-{mapping,fulltree,mockoracle-deleted,mockoracle-src-still-present}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-24-mapping.log`
  - [ ] `.sisyphus/evidence/task-24-fulltree.log`
  - [ ] `.sisyphus/evidence/task-24-mockoracle-deleted.log`
  - [ ] `.sisyphus/evidence/task-24-mockoracle-src-still-present.log`

  **Commit**: YES
  - Message: `refactor(test): delete obsolete MockPriceOracle test + finalize mapping`

---

### Wave 4 — Hardhat test port (Chunk 4) — MAX PARALLEL

> All Wave 4 tasks share a common pattern: **vendor upstream Venus tests + use vendored upstream fixtures + verify `pnpm hardhat test --grep <subsystem>` green**. Each task is per-subsystem to maximize parallel agent throughput. Use Wave 1's vendored `tests/hardhat/` and `deploy/` as the source.
>
> **ANTI-CREEP RULE (per user clarification)**: Wave 4 is **vendor + run**. DO NOT author new Endure-side fixtures, "spin up" new test infrastructure, or build new mocks. If a vendored upstream Venus test passes against vendored upstream fixtures in a local Hardhat network — green. If it fails because of unfixable BSC/BNB/mainnet-RPC assumptions — skip with rationale in `tests/hardhat/SKIPPED.md` (T38). The ONLY adaptations allowed are (a) `it.skip` invocations on individual tests with rationale, (b) Hardhat config / path-mapping (already done in T25b). NO new Endure-authored Solidity files, NO new Endure-authored TypeScript fixtures.
>
> **Common references for Wave 4 tasks**:
> - Vendored upstream tests at `packages/contracts/tests/hardhat/<subsystem>/` (from T3)
> - Vendored deploy scripts at `packages/contracts/deploy/` (from T4)
> - Vendored test helpers at `packages/contracts/src/test-helpers/venus/` (from T5)
> - `hardhat.config.ts` (from T2)
> - Spec section "Hardhat side: full upstream suite" (lines 641–667)

- [ ] 25. **Resolve 3 broken harness files (VRTConverter / VRTVault / XVSVesting)**

  **What to do**:
  - Per finding F5, three Venus harness files have upstream-broken relative imports under Foundry path resolution: `VRTConverterHarness.sol`, `VRTVaultHarness.sol`, `XVSVestingHarness.sol`
  - **APPROACH (LOCKED — patch is the only working path for both toolchains)**: Re-vendor the 3 files into `packages/contracts/src/test-helpers/venus/` (Stage A omitted them precisely because Foundry compiles every `.sol` under `src/` regardless of import reachability and these files' broken `../../contracts/X` imports caused build failures). Patch each broken import (1-line edit: `../../contracts/X` → `../X` to resolve from the new location). Record a 3-line documented Stance B deviation in `FORK_MANIFEST.md` Section 6.2 (one row per harness file: file path + original import + patched import).
  - **WHY NOT "rely on Hardhat resolution"**: Foundry doesn't honor Hardhat's path resolution. Even if Hardhat could find `../../contracts/X`, Foundry's `forge build` traverses every `.sol` under `src/` and would fail. The patch approach is the only one that works for BOTH `forge build` AND `pnpm hardhat compile`.
  - Verify both toolchains: `forge build --root packages/contracts` AND `pnpm --filter @endure/contracts hardhat compile` must both exit 0
  - Document the patch in `FORK_MANIFEST.md` Section 6.2 with: file path, exact `import` line before patch, exact `import` line after patch, rationale ("upstream relative path assumes Hardhat repo-root resolution; patched to resolve under Endure's `src/test-helpers/venus/` layout")

  **Must NOT do**:
  - Do NOT silently skip these files — they are required by VRT and XVSVesting Hardhat tests (T32, T33)
  - Do NOT use the original "rely on Hardhat resolution" approach — confirmed broken for Foundry per Stage A
  - Do NOT modify any logic, only the import paths (3 single-line edits total)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — Path-resolution puzzle with two valid solutions
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent within Wave 4
  - **Parallel Group**: Wave 4
  - **Blocks**: T32 (XVS), T33 (VRT) — those subsystems need the harnesses
  - **Blocked By**: T24

  **References**:

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:60-65` — finding F5 with both options
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:30` — note that Stage A omitted these; Stage B Chunk 4 must address

  **WHY Each Reference Matters**:
  - F5 explicitly enumerates the resolution options; choosing arbitrarily without recording the choice is a Stance B audit failure

  **Acceptance Criteria**:
  - [ ] All 3 harness files exist in a way Hardhat can compile
  - [ ] `pnpm --filter @endure/contracts hardhat compile` exits 0
  - [ ] `FORK_MANIFEST.md` Section 6.2 documents the choice + rationale

  **QA Scenarios**:

  ```
  Scenario: Harness files resolved
    Tool: Bash
    Preconditions: T24 done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat compile 2>&1 | tee .sisyphus/evidence/task-25-compile.log
      2. Run: grep -A 5 "VRTConverterHarness\|VRTVaultHarness\|XVSVestingHarness" packages/contracts/FORK_MANIFEST.md | tee .sisyphus/evidence/task-25-manifest.log
    Expected Result: Compile clean, manifest documents resolution
    Failure Indicators: Compile error citing harness imports, missing manifest entry
    Evidence: .sisyphus/evidence/task-25-{compile,manifest}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-25-compile.log`
  - [ ] `.sisyphus/evidence/task-25-manifest.log`

  **Commit**: YES
  - Message: `chore(venus): resolve 3 broken harness files for hardhat compile`

- [ ] 25b. **Hardhat path-mapping foundation — solve once, propagate to all Wave 4 subsystems**

  **What to do**:
  - **PROBLEM**: Venus's vendored Hardhat tests (in `tests/hardhat/<subsystem>/*.ts`) and deploy scripts (in `deploy/`) use upstream-relative imports like `../../contracts/Foo/Bar.sol` and `../../deploy/...` that assume Venus's repo layout (`<root>/contracts/`, `<root>/tests/hardhat/`, `<root>/deploy/`). Endure's layout differs: contracts live at `packages/contracts/src/venus-staging/...` (during staging) and `packages/contracts/src/...` (post Chunk 5b). Without an explicit fix, EVERY Wave 4 subsystem task (T26–T37) would independently hit and re-solve the same path-resolution failure.
  - This task solves it ONCE in `packages/contracts/hardhat.config.ts`, validates with a single trivial test, and lets T26–T37 inherit the fix.
  - Update `packages/contracts/hardhat.config.ts`:
    - Set `paths.sources = "./src/venus-staging"` (during staging period; T46 commit B updates to `"./src"`)
    - Set `paths.tests = "./tests/hardhat"`
    - Set `paths.deploy = "./deploy"`
    - Set `paths.deployments = "./deployments"`
    - Set `paths.cache = "./cache_hardhat"`
    - Set `paths.artifacts = "./artifacts"`
    - Configure compiler `remappings` (or use a `hardhat-preprocessor`-style import rewriter) so `import "../../contracts/X.sol"` from a vendored test resolves to `packages/contracts/src/venus-staging/X.sol`
    - For `@venusprotocol/*` imports, ensure Hardhat resolves them to `lib/venusprotocol-*/contracts/...` matching the Foundry remappings
  - Validate by running ONE pre-existing Venus test end-to-end (pick the simplest — e.g., a small InterestRateModels test or a Comptroller smoke test from `tests/hardhat/`) — must compile + execute + pass
  - Document the path-mapping choice in `tests/hardhat/README.md` (created in T3) so T26–T37 executors don't second-guess it
  - **Plan to handle T46 transition**: `hardhat.config.ts` `paths.sources` flips from `./src/venus-staging` → `./src` as part of T46's mass-move; this task documents the pre-T46 setting and leaves a comment in the config

  **Must NOT do**:
  - Do NOT modify any vendored Hardhat test file (Stance B violation; tests are byte-identical to upstream)
  - Do NOT modify any vendored Hardhat deploy script
  - Do NOT skip validation — running ONE test end-to-end is the whole point of having this task

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — Hardhat config + path-resolution debugging requires careful first-time problem-solving
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO — gates Wave 4 entirely
  - **Parallel Group**: Wave 4 prerequisite (sits between T25 and T26)
  - **Blocks**: T26–T37 (every subsystem task depends on path mapping working)
  - **Blocked By**: T2, T3, T4, T5, T24, T25

  **References**:

  **Pattern References**:
  - `packages/contracts/hardhat.config.ts` (created in T2)
  - `packages/contracts/tests/hardhat/` (vendored in T3)
  - `packages/contracts/deploy/` (vendored in T4)
  - `packages/contracts/remappings.txt` (Foundry remappings — Hardhat must mirror)

  **External References**:
  - Hardhat docs: https://hardhat.org/hardhat-runner/docs/config — paths, remappings, hardhat-preprocessor
  - Venus upstream `hardhat.config.ts` at commit `6400a067` — for the proven dual-compiler + path setup

  **WHY Each Reference Matters**:
  - Solving path mapping ONCE here removes a 12x-duplicated risk from Wave 4 (T26–T37 are otherwise blocked)
  - Validating with one real test catches misconfig BEFORE 11 parallel tasks all silently fail

  **Acceptance Criteria**:
  - [ ] `packages/contracts/hardhat.config.ts` declares all 6 `paths.*` keys explicitly
  - [ ] `packages/contracts/hardhat.config.ts` declares Hardhat-side remappings or preprocessor wiring matching Foundry's `remappings.txt`
  - [ ] `pnpm --filter @endure/contracts hardhat compile` exits 0 (T6 still green)
  - [ ] ONE chosen Venus test runs end-to-end via `pnpm hardhat test --grep "<chosen-test-name>"` and exits 0
  - [ ] `tests/hardhat/README.md` documents the path-mapping choice for downstream task executors
  - [ ] Comment in `hardhat.config.ts` flags that `paths.sources` flips from `./src/venus-staging` → `./src` in T46

  **QA Scenarios**:

  ```
  Scenario: Path mapping foundation works end-to-end
    Tool: Bash
    Preconditions: T2, T3, T4, T5, T24, T25 done
    Steps:
      1. Run: cat packages/contracts/hardhat.config.ts | grep -E "paths\.|remappings|preprocessor" | tee .sisyphus/evidence/task-25b-config.log
      2. Run: pnpm --filter @endure/contracts hardhat compile 2>&1 | tee .sisyphus/evidence/task-25b-compile.log
      3. Pick one simple test path from packages/contracts/tests/hardhat/InterestRateModels/ (e.g., the first .ts file)
      4. Run: pnpm --filter @endure/contracts hardhat test --grep "<chosen-test-name>" 2>&1 | tee .sisyphus/evidence/task-25b-validate.log
      5. Assert: config has all paths + remappings; compile clean; chosen test passes
    Expected Result: Hardhat resolves vendored test imports correctly; one full Venus test runs green
    Failure Indicators: Compile error mentioning import path; "Cannot find module"; test failure due to missing artifact
    Evidence: .sisyphus/evidence/task-25b-{config,compile,validate}.log

  Scenario: README documents the resolution for downstream tasks
    Tool: Bash
    Preconditions: T25b implementation done
    Steps:
      1. Run: grep -E "paths|sources|venus-staging|T46" packages/contracts/tests/hardhat/README.md | tee .sisyphus/evidence/task-25b-readme.log
      2. Assert: README mentions paths.sources, the venus-staging vs src/ transition at T46, and the import-resolution approach
    Expected Result: README is a usable runbook for T26–T37 executors
    Failure Indicators: README missing or vague
    Evidence: .sisyphus/evidence/task-25b-readme.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-25b-config.log`
  - [ ] `.sisyphus/evidence/task-25b-compile.log`
  - [ ] `.sisyphus/evidence/task-25b-validate.log`
  - [ ] `.sisyphus/evidence/task-25b-readme.log`

  **Commit**: YES
  - Message: `chore(hardhat): solve venus test+deploy path mapping (foundation for wave 4)`
  - Files: `packages/contracts/hardhat.config.ts`, `packages/contracts/tests/hardhat/README.md`
  - Pre-commit: chosen test passes via `pnpm hardhat test --grep`

- [ ] 25c. **Resolve `lib/venusprotocol-*` git commit SHAs + record in FORK_MANIFEST**

  **What to do**:
  - **PROBLEM**: Stage A vendored 5 `@venusprotocol/*` npm packages into `packages/contracts/lib/venusprotocol-*/` by extracting them from the Venus main repo's `node_modules/` at commit `6400a067`. Each `VENDOR.md` records the npm version (e.g., `2.13.0`) and the parent Venus commit. To make Stance B's byte-identity audit airtight, this task records BOTH (a) the parent Venus commit (already present, suitable for Approach A audit) AND (b) the standalone-repo git tag/SHA (Approach B audit, supplementary).
  - **PRE-FLIGHT (60-second check before doing the work)**: Verify that Venus repo at `6400a067` ships a pinned `package-lock.json` so Approach A's `npm install` is deterministic. If absent, Approach A audit drifts on every CI run.
    - Run: `gh api repos/VenusProtocol/venus-protocol/contents/package-lock.json?ref=6400a067114a101bd3bebfca2a4bd06480e84831 | jq -r '.size'`
    - Expected: returns a non-zero file size (file exists at that commit)
    - If pre-flight FAILS (404 or size 0): document in FORK_MANIFEST.md Section 6.7 prelude that "Approach A reproducibility is BEST-EFFORT only; Venus does not ship a pinned `package-lock.json` at the pinned commit. Approach B (per-package SHA) is recommended primary verification despite extra clones." DO NOT silently proceed without this note.
  - **TWO AUDIT APPROACHES** (per Metis review):
    - **Approach A (PRIMARY for T40)**: Clone Venus main repo at `6400a067`, run `npm install` in CI, byte-compare `node_modules/@venusprotocol/<pkg>/contracts/**` against `lib/venusprotocol-<pkg>/contracts/**`. This exactly mirrors how files were vendored. Pro: deterministic, single repo clone. Con: requires `npm install` in CI.
    - **Approach B (SUPPLEMENTARY)**: Resolve each npm version to its standalone-repo git tag/SHA, clone each repo, byte-compare. Pro: source-of-truth git audit. Con: 5 extra clones, may fail for slim versions.
    - This task records data needed for BOTH approaches in FORK_MANIFEST. T40 implements Approach A as primary; Approach B is recorded for documentation completeness.
  - For each of the 5 packages, read the npm version from VENDOR.md (e.g., governance-contracts v2.13.0, oracle v2.10.0, etc.)
  - **CORRECT API CALL** (Metis-confirmed): VenusProtocol repos use `semantic-release` which creates git **tags** (format `v{version}` — `v` prefix is mandatory) but does NOT create GitHub Releases. Therefore:
    - **DO NOT** use `gh api repos/VenusProtocol/<repo>/releases` (returns empty array — confirmed by librarian)
    - **DO USE** `gh api repos/VenusProtocol/<repo>/git/ref/tags/v<version>` to resolve a tag → commit SHA
    - Example: `gh api repos/VenusProtocol/governance-contracts/git/ref/tags/v2.13.0 | jq -r '.object.sha'` → returns the SHA
  - **FALLBACK for "slim" versions or missing tags**: Some VenusProtocol packages publish `*-slim` npm versions that have no git tag. If `gh api` returns 404 for any package, record `source: venus-protocol@6400a067 node_modules` in VENDOR.md instead of a standalone SHA, and document the package as "audited via Approach A only" in FORK_MANIFEST Section 6.7.
  - For each package, update its `lib/venusprotocol-*/VENDOR.md` with:
    ```
    - Vendored from: venus-protocol@6400a067 node_modules (Approach A audit source)
    - Standalone repo: VenusProtocol/<repo>
    - Standalone tag: v<version>
    - Standalone commit: <resolved SHA from gh api>  OR  "N/A — slim version, no git tag, audit via Approach A only"
    ```
  - Add a new section to `packages/contracts/FORK_MANIFEST.md` (Section 6.7):
    ```
    ## 6.7 lib/venusprotocol-* dependency package pins

    Audit posture: Approach A is primary (clone venus-protocol@6400a067, npm install, byte-compare).
    Approach B SHAs recorded for documentation; T40 uses Approach A for CI.

    | Package | npm version | Upstream repo | Standalone tag | Standalone commit (Approach B) |
    |---------|-------------|---------------|----------------|-------------------------------|
    | @venusprotocol/governance-contracts | 2.13.0 | VenusProtocol/governance-contracts | v2.13.0 | <SHA> |
    | @venusprotocol/oracle | 2.10.0 | VenusProtocol/oracle | v2.10.0 | <SHA> |
    | @venusprotocol/protocol-reserve | x.x.x | VenusProtocol/protocol-reserve | v<x.x.x> | <SHA> |
    | @venusprotocol/solidity-utilities | x.x.x | VenusProtocol/solidity-utilities | v<x.x.x> | <SHA> |
    | @venusprotocol/token-bridge | x.x.x | VenusProtocol/token-bridge | v<x.x.x> | <SHA> |
    ```
  - These SHAs (Approach B) and the Venus parent commit (Approach A) become the canonical inputs for T40's Stance B script

  **Must NOT do**:
  - Do NOT modify any vendored Solidity file in any of the `lib/venusprotocol-*/` packages (Stance B violation)
  - Do NOT use only the npm version — the audit needs the git SHA
  - Do NOT skip a package because its SHA is hard to find — every audit-relevant package needs a SHA

  **Recommended Agent Profile**:
  - **Category**: `quick` — GitHub API queries + manifest editing
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES — independent of T25, T25b, T26
  - **Parallel Group**: Wave 4 prerequisite (sits in the T25 family); blocks T40
  - **Blocks**: T40 (Stance B audit needs the SHAs)
  - **Blocked By**: T24

  **References**:

  **Pattern References**:
  - `packages/contracts/lib/venusprotocol-governance-contracts/VENDOR.md` — current format (npm version + parent Venus commit only)
  - `packages/contracts/FORK_MANIFEST.md` Section 6.3 (current dependency table — has versions, needs SHAs added)

  **External References**:
  - GitHub releases: `https://github.com/VenusProtocol/governance-contracts/releases`, `https://github.com/VenusProtocol/oracle/releases`, etc.
  - `gh api repos/<org>/<repo>/git/refs/tags/v<version>` to resolve a tag → commit SHA

  **WHY Each Reference Matters**:
  - Without SHAs, Stance B audit silently skips `lib/venusprotocol-*/contracts/**` (or hardcodes a wrong SHA), undermining the byte-identity guarantee for ~131 vendored Solidity files

  **Acceptance Criteria**:
  - [ ] Each of the 5 `lib/venusprotocol-*/VENDOR.md` files now records BOTH the Venus parent commit (Approach A source) AND the standalone-repo SHA (Approach B) OR an explicit "N/A — slim version" fallback
  - [ ] `FORK_MANIFEST.md` Section 6.7 has a 5-row table with the 5-column shape above (package, npm version, upstream repo, standalone tag, standalone commit)
  - [ ] Section 6.7 prelude paragraph explicitly states "Approach A is primary; Approach B is supplementary"
  - [ ] Each non-N/A SHA is verifiable: `gh api repos/VenusProtocol/<repo>/git/ref/tags/v<version>` returns 200 OK with the recorded SHA in `.object.sha`
  - [ ] No Solidity files modified

  **QA Scenarios**:

  ```
  Scenario: All 5 dependency tag SHAs resolved (Approach B) via correct API
    Tool: Bash
    Preconditions: T24 done; gh CLI authenticated
    Steps:
      1. For each package, read VENDOR.md and extract the npm version
      2. For each (package, version): RESOLVED=$(gh api repos/VenusProtocol/<repo>/git/ref/tags/v<version> 2>/dev/null | jq -r '.object.sha // "N/A"'); echo "<package> v<version> -> $RESOLVED" | tee -a .sisyphus/evidence/task-25c-shas.log
      3. For non-N/A SHAs, verify by re-running: gh api repos/VenusProtocol/<repo>/git/commits/<SHA> | jq -r '.sha' (must match)
      4. Run: grep -A 10 "6.7\|dependency package pins" packages/contracts/FORK_MANIFEST.md | tee .sisyphus/evidence/task-25c-manifest.log
      5. Assert: 5 packages enumerated; non-N/A SHAs verified; manifest table has 5 rows + Approach A/B prelude
    Expected Result: All resolvable SHAs recorded; slim/missing tags fall back to N/A with documented reason
    Failure Indicators: Use of `gh api .../releases` (will return empty); missing fallback for any 404; manifest missing or incomplete
    Evidence: .sisyphus/evidence/task-25c-{shas,manifest}.log

  Scenario: Approach A pre-requisite — Venus parent commit accessible
    Tool: Bash
    Preconditions: T25c implementation done
    Steps:
      1. Run: gh api repos/VenusProtocol/venus-protocol/git/commits/6400a067114a101bd3bebfca2a4bd06480e84831 | jq -r '.sha' | tee .sisyphus/evidence/task-25c-venus-commit.log
      2. Assert: returns the commit SHA (proves the parent commit T40 will clone is accessible)
    Expected Result: Venus parent commit confirmed accessible
    Failure Indicators: 404 (commit deleted upstream — would block T40 entirely)
    Evidence: .sisyphus/evidence/task-25c-venus-commit.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-25c-shas.log`
  - [ ] `.sisyphus/evidence/task-25c-manifest.log`

  **Commit**: YES
  - Message: `chore(deps): resolve venusprotocol package git commit SHAs for stance b audit`
  - Files: 5× `packages/contracts/lib/venusprotocol-*/VENDOR.md`, `packages/contracts/FORK_MANIFEST.md`
  - Pre-commit: all 5 SHAs verified via `gh api`

- [ ] 26. **Vendor Venus Comptroller/Diamond Hardhat tests + fixtures green**

  **What to do**:
  - Tests already vendored at `tests/hardhat/Comptroller/` (and Diamond subdir if upstream uses one) by T3
  - Adapt `deploy/` scripts so `hardhat-deploy` can deploy the full Comptroller diamond (Unitroller + Diamond + 4 facets + ComptrollerLens) for these tests
  - Run: `pnpm --filter @endure/contracts hardhat test --grep "Comptroller|Diamond"` → all tests pass
  - Document any test that's been adjusted (e.g., for BSC-block-number references) in `tests/hardhat/SKIPPED.md` (T38 will consolidate)

  **Must NOT do**:
  - Do NOT modify upstream test logic (Stance B violation); only adapt fixtures and skip with `it.skip` if necessary
  - Do NOT use Foundry's deployed `addresses.json` (state isolation)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` — Largest subsystem; needs careful fixture work
  - **Skills**: `[]`

  **Parallelization**: YES; Wave 4
  - **Blocks**: T39 (collective Hardhat test gate)
  - **Blocked By**: T24, T2 (config), T25b (path mapping)

  **References**: per Wave 4 common refs above; spec lines 644–646 (Comptroller/Diamond row in fixture table)

  **WHY**: Comptroller is the foundational subsystem — all other Hardhat tests depend on a working Comptroller fixture.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "Comptroller|Diamond"` exits 0
  - [ ] No upstream test file modified (Stance B clean)
  - [ ] If any test skipped: documented in SKIPPED.md (T38)

  **QA Scenarios**:

  ```
  Scenario: Comptroller subsystem tests pass
    Tool: Bash
    Preconditions: T2, T24 done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "Comptroller" 2>&1 | tee .sisyphus/evidence/task-26-comp.log
      2. Run: pnpm --filter @endure/contracts hardhat test --grep "Diamond" 2>&1 | tee .sisyphus/evidence/task-26-diamond.log
    Expected Result: All tests pass (or explicitly skipped + documented)
    Failure Indicators: Any test failure not in SKIPPED.md
    Evidence: .sisyphus/evidence/task-26-{comp,diamond}.log
  ```

  **Evidence to Capture**: `.sisyphus/evidence/task-26-{comp,diamond}.log`

  **Commit**: YES — `test(hardhat): vendor venus comptroller/diamond fixtures green`

- [ ] 27. **Vendor Venus Unitroller Hardhat tests + fixtures green**

  **What to do**: Same pattern as T26 but for `tests/hardhat/Unitroller/`. Run `pnpm hardhat test --grep "Unitroller"` → green.

  **Must NOT do**: Modify upstream tests; bridge state with Foundry.

  **Recommended Agent Profile**: `quick` (smaller subsystem)
  **Parallelization**: YES; Wave 4; blocks T39; blocked by T24, T2, T25b.
  **References**: per Wave 4 common refs; spec line 647.
  **WHY**: Unitroller is straightforward; fixtures already mostly work since spike used Unitroller.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "Unitroller"` exits 0

  **QA Scenarios**:

  ```
  Scenario: Unitroller tests pass
    Tool: Bash
    Preconditions: T2, T24 done; T26 (Comptroller) green
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "Unitroller" 2>&1 | tee .sisyphus/evidence/task-27-unitroller.log
      2. Assert: log contains "passing" with non-zero count and zero "failing"
      3. Assert: exit code 0
    Expected Result: All Unitroller tests pass; exit 0; no failures unless documented in tests/hardhat/SKIPPED.md (T38)
    Failure Indicators: Any test failure not in SKIPPED.md; exit code non-zero; "0 passing" reported
    Evidence: .sisyphus/evidence/task-27-unitroller.log
  ```

  **Commit**: YES — `test(hardhat): vendor venus unitroller fixtures green`

- [ ] 28. **Vendor Venus VToken Hardhat tests (Immutable + Delegate + Delegator) + fixtures green**

  **What to do**: Tests at `tests/hardhat/VToken/`. Fixtures need to deploy all 3 variants: `VBep20Immutable`, `VBep20Delegate` (impl), `VBep20Delegator` (proxy pointing at Delegate). Endure deploys only Immutable but Hardhat tests cover all. Run `pnpm hardhat test --grep "VToken"` → green.

  **Must NOT do**: Modify upstream tests; deploy these variants on Anvil (Hardhat-fixture-only).

  **Recommended Agent Profile**: `unspecified-high` — multiple delegate variants to wire correctly
  **Parallelization**: YES; Wave 4; blocks T39; blocked by T24, T2, T25b.
  **References**: spec line 648 (VToken fixture table row).
  **WHY**: VToken is the second-most-tested subsystem after Comptroller.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "VToken"` exits 0; covers all 3 variants

  **QA Scenarios**:

  ```
  Scenario: VToken (all 3 variants) tests pass
    Tool: Bash
    Preconditions: T2, T24 done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "VToken" 2>&1 | tee .sisyphus/evidence/task-28-vtoken.log
      2. Assert: log shows tests covering VBep20Immutable, VBep20Delegate, AND VBep20Delegator (all 3 variants exercised)
      3. Assert: exit code 0; no failures unless in SKIPPED.md
    Expected Result: All VToken tests across the 3 variants pass; fixtures correctly deploy proxy + impl pairs
    Failure Indicators: Any test failure not in SKIPPED.md; only 1-2 variants exercised (incomplete fixture); proxy delegation revert
    Evidence: .sisyphus/evidence/task-28-vtoken.log
  ```

  **Commit**: YES — `test(hardhat): vendor venus vtoken fixtures (immutable+delegate+delegator) green`

- [ ] 29. **Vendor Venus InterestRateModels Hardhat tests + fixtures green**

  **What to do**: Tests at `tests/hardhat/InterestRateModels/`. Fixtures deploy `TwoKinksInterestRateModel` (already in Endure surface) and any other IRMs upstream tests cover. Run `pnpm hardhat test --grep "InterestRateModel"` → green.

  **Must NOT do**: Modify upstream tests.

  **Recommended Agent Profile**: `quick` — small subsystem, mostly numeric assertions
  **Parallelization**: YES; Wave 4; blocks T39; blocked by T24, T2, T25b.
  **References**: spec line 649.
  **WHY**: IRM tests are pure-function; fewest fixture dependencies.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "InterestRateModel"` exits 0

  **QA Scenarios**:

  ```
  Scenario: IRM tests pass
    Tool: Bash
    Preconditions: T2, T24 done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "InterestRateModel" 2>&1 | tee .sisyphus/evidence/task-29-irm.log
      2. Assert: log shows tests covering TwoKinksInterestRateModel + any other IRMs upstream tests reference
      3. Assert: exit code 0; no failures unless in SKIPPED.md
    Expected Result: All IRM tests pass; numeric assertions hold against Venus's TwoKinks return semantics
    Failure Indicators: Any test failure not in SKIPPED.md; numeric divergence (e.g., utilization-rate calculation mismatch); exit non-zero
    Evidence: .sisyphus/evidence/task-29-irm.log
  ```

  **Commit**: YES — `test(hardhat): vendor venus IRM fixtures green`

- [ ] 30. **Vendor Venus VAI subsystem (Controller + Vault + token + PegStability) Hardhat tests + fixtures green**

  **What to do**: Tests at `tests/hardhat/VAI/`. Fixtures deploy `VAIController`, `VAIVault`, `VAI` token, `PegStability`. These are Hardhat-fixture-only — Endure does NOT expose VAI as a feature. Run `pnpm hardhat test --grep "VAI|PegStability"` → green.

  **Must NOT do**: Add VAI to Endure's deploy helper. Do not call VAI from Foundry tests.

  **Recommended Agent Profile**: `unspecified-high` — multi-contract fixture
  **Parallelization**: YES; Wave 4; blocks T39; blocked by T24, T2, T25b.
  **References**: spec line 650.
  **WHY**: VAI fixture infrastructure is ~30% of Chunk 4's work but it's Hardhat-only — never touches Endure's surface.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "VAI|PegStability"` exits 0
  - [ ] No VAI references in `EndureDeployHelper.sol` or any `test/endure/` file

  **QA Scenarios**:

  ```
  Scenario: VAI subsystem isolated to Hardhat
    Tool: Bash
    Preconditions: T2, T24 done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "VAI" 2>&1 | tee .sisyphus/evidence/task-30-vai.log
      2. Run: grep -r "VAI" packages/contracts/test/endure/ packages/contracts/test/helper/EndureDeployHelper.sol packages/deploy/src/ 2>&1 | tee .sisyphus/evidence/task-30-isolation.log
      3. Assert: tests pass; isolation grep returns 0 matches in code (or only matches in comments)
      4. Assert: exit code 0 for hardhat test; no failures unless in SKIPPED.md
    Expected Result: VAI subsystem tests pass in Hardhat; ZERO references to VAI in Endure's deploy surface (Foundry/Anvil deployment path remains VAI-free per Decision: VAI vendored only)
    Failure Indicators: Any test failure not in SKIPPED.md; ANY non-comment reference to VAI in EndureDeployHelper.sol or DeployLocal.s.sol (would indicate accidental promotion of VAI to Endure feature)
    Evidence: .sisyphus/evidence/task-30-{vai,isolation}.log
  ```

  **Commit**: YES — `test(hardhat): vendor venus VAI fixtures (hardhat-only) green`

- [ ] 31. **Vendor Venus Prime + PrimeLiquidityProvider Hardhat tests + fixtures green**

  **What to do**: Tests at `tests/hardhat/Prime/`. Fixtures deploy `Prime`, `PrimeLiquidityProvider`. Hardhat-fixture-only. Run `pnpm hardhat test --grep "Prime"` → green.

  **Must NOT do**: Add Prime to Endure surface.

  **Recommended Agent Profile**: `unspecified-high`
  **Parallelization**: YES; Wave 4; blocks T39; blocked by T24, T2, T25b.
  **References**: spec line 651.
  **WHY**: Same isolation rationale as VAI.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "Prime"` exits 0
  - [ ] No Prime references in Endure surface

  **QA Scenarios**:

  ```
  Scenario: Prime tests pass + isolated
    Tool: Bash
    Preconditions: T2, T24 done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "Prime" 2>&1 | tee .sisyphus/evidence/task-31-prime.log
      2. Run: grep -r "Prime" packages/contracts/test/endure/ packages/contracts/test/helper/EndureDeployHelper.sol 2>&1 | tee .sisyphus/evidence/task-31-isolation.log
      3. Assert: hardhat test exit 0; no failures unless in SKIPPED.md
      4. Assert: isolation grep returns 0 non-comment matches in Endure surface
    Expected Result: Prime + PrimeLiquidityProvider tests pass in Hardhat; Endure's deploy surface contains zero Prime references (vendored only, never deployed by Endure)
    Failure Indicators: Any test failure not in SKIPPED.md; Prime contract referenced in EndureDeployHelper.sol or DeployLocal.s.sol
    Evidence: .sisyphus/evidence/task-31-{prime,isolation}.log
  ```

  **Commit**: YES — `test(hardhat): vendor venus Prime fixtures green`

- [ ] 32. **Vendor Venus XVS (Vault + Store + token) Hardhat tests + fixtures green**

  **What to do**: Tests at `tests/hardhat/XVS/`. Depends on T25's harness resolution for `XVSVestingHarness.sol`. Fixtures deploy `XVSVault`, `XVSStore`, `XVS` token. Run `pnpm hardhat test --grep "XVS"` → green.

  **Must NOT do**: Add XVS to Endure surface.

  **Recommended Agent Profile**: `unspecified-high`
  **Parallelization**: YES; Wave 4; blocks T39; blocked by T24, T2, T25, T25b.
  **References**: spec line 652.
  **WHY**: XVSVesting requires the harness file from T25.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "XVS"` exits 0
  - [ ] No XVS references in Endure surface OUTSIDE the documented RewardFacet carve-out (allowed: `src/endure/MockXVS.sol`, `test/endure/venus/RewardFacetEnable.t.sol`; everything else must be XVS-free)

  **QA Scenarios**:

  ```
  Scenario: XVS tests pass with harness resolved (with documented RewardFacet carve-out)
    Tool: Bash
    Preconditions: T2, T24, T25 (harness resolution) done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "XVS" 2>&1 | tee .sisyphus/evidence/task-32-xvs.log
      2. Run: grep -r "XVS" packages/contracts/test/endure/ packages/contracts/test/helper/EndureDeployHelperVenus.sol --exclude-dir=venus 2>&1 | tee .sisyphus/evidence/task-32-isolation.log
         Note: `--exclude-dir=venus` matches directory NAMES (not paths). Currently only `test/endure/venus/` is excluded. **Fragility**: if a future task creates another `venus/`-named directory inside the search paths (`test/endure/`, `test/helper/`), it would be silently excluded. Re-evaluate this exclusion if the directory layout changes. The carve-out (RewardFacetEnable.t.sol) is documented in FORK_MANIFEST and Documented Deviations.
      3. Run: ls packages/contracts/src/endure/MockXVS.sol | tee .sisyphus/evidence/task-32-mockxvs-allowed.log
         (MockXVS.sol IS allowed in src/endure/ per the documented RewardFacet carve-out — do NOT flag this as an isolation violation)
      4. Assert: XVSVestingHarness compiles cleanly under Hardhat (no import errors)
      5. Assert: hardhat test exit 0; isolation grep returns 0 non-comment matches OUTSIDE the carve-out (test/endure/venus/RewardFacetEnable.t.sol + src/endure/MockXVS.sol are explicitly permitted)
    Expected Result: XVS subsystem tests pass; XVSVestingHarness resolved via T25's chosen approach (re-vendor or patch); zero XVS in Endure surface
    Failure Indicators: Harness import errors (T25 incomplete); any test failure not in SKIPPED.md; XVS in EndureDeployHelper.sol
    Evidence: .sisyphus/evidence/task-32-{xvs,isolation}.log
  ```

  **Commit**: YES — `test(hardhat): vendor venus XVS fixtures green`

- [ ] 33. **Vendor Venus VRT (Vault + Converter + token) Hardhat tests + fixtures green**

  **What to do**: Tests at `tests/hardhat/VRT/`. Depends on T25's harness resolution for VRT harnesses. Fixtures deploy `VRTVault`, `VRTConverter`, `VRT` token. Run `pnpm hardhat test --grep "VRT"` → green.

  **Recommended Agent Profile**: `unspecified-high`
  **Parallelization**: YES; Wave 4; blocks T39; blocked by T24, T2, T25, T25b.
  **References**: spec line 653.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "VRT"` exits 0; no VRT references in Endure surface

  **QA Scenarios**:

  ```
  Scenario: VRT tests pass
    Tool: Bash
    Preconditions: T2, T24, T25 (harness resolution) done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "VRT" 2>&1 | tee .sisyphus/evidence/task-33-vrt.log
      2. Run: grep -r "VRT" packages/contracts/test/endure/ packages/contracts/test/helper/EndureDeployHelper.sol 2>&1 | tee .sisyphus/evidence/task-33-isolation.log
      3. Assert: VRTConverterHarness + VRTVaultHarness compile cleanly under Hardhat (no import errors from T25's fix)
      4. Assert: hardhat test exit 0; isolation grep returns 0 non-comment matches in Endure surface
    Expected Result: VRT subsystem tests pass; both VRT harnesses resolved; zero VRT in Endure surface
    Failure Indicators: Harness import errors; any test failure not in SKIPPED.md; VRT in EndureDeployHelper.sol
    Evidence: .sisyphus/evidence/task-33-{vrt,isolation}.log
  ```

  **Commit**: YES — `test(hardhat): vendor venus VRT fixtures green`

- [ ] 34. **Vendor Venus Liquidator Hardhat tests + fixtures green**

  **What to do**: Tests at `tests/hardhat/Liquidator/`. Fixtures deploy external `Liquidator` contract. Hardhat-fixture-only — Endure exposes ONLY direct vToken liquidation. Run `pnpm hardhat test --grep "Liquidator"` → green.

  **Must NOT do**: Add Liquidator to Endure deploy helper or `DeployLocal.s.sol`.

  **Recommended Agent Profile**: `unspecified-high`
  **Parallelization**: YES; Wave 4; blocks T39; blocked by T24, T2, T25b.
  **References**: spec line 654.
  **WHY**: Critical isolation — Endure's "direct vToken liquidation only" decision means external Liquidator can NEVER appear in Endure's deployed surface.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "Liquidator"` exits 0
  - [ ] No Liquidator references in `EndureDeployHelper.sol` or `packages/deploy/src/DeployLocal.s.sol`

  **QA Scenarios**:

  ```
  Scenario: Liquidator tests pass + isolated from Endure
    Tool: Bash
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "Liquidator" 2>&1 | tee .sisyphus/evidence/task-34-liq.log
      2. Run: grep -r "Liquidator" packages/contracts/test/helper/EndureDeployHelper.sol packages/deploy/src/ 2>&1 | tee .sisyphus/evidence/task-34-isolation.log
    Expected Result: tests green; isolation grep finds 0 matches in helper/deploy
    Evidence: .sisyphus/evidence/task-34-{liq,isolation}.log
  ```

  **Commit**: YES — `test(hardhat): vendor venus liquidator fixtures (hardhat-only) green`

- [ ] 35. **Vendor Venus DelegateBorrowers (SwapDebtDelegate + MoveDebtDelegate) Hardhat tests + fixtures green**

  **What to do**: Tests at `tests/hardhat/DelegateBorrowers/`. Fixtures deploy `SwapDebtDelegate`, `MoveDebtDelegate`. Hardhat-fixture-only. Run `pnpm hardhat test --grep "Delegate"` → green.

  **Recommended Agent Profile**: `unspecified-high`
  **Parallelization**: YES; Wave 4; blocks T39; blocked by T24, T2, T25b.
  **References**: spec line 655.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "Delegate"` exits 0; no Delegate references in Endure surface

  **QA Scenarios**:

  ```
  Scenario: DelegateBorrower tests pass
    Tool: Bash
    Preconditions: T2, T24 done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "Delegate" 2>&1 | tee .sisyphus/evidence/task-35-delegate.log
      2. Run: grep -r "SwapDebtDelegate\|MoveDebtDelegate" packages/contracts/test/endure/ packages/contracts/test/helper/EndureDeployHelper.sol 2>&1 | tee .sisyphus/evidence/task-35-isolation.log
      3. Assert: hardhat test exit 0; isolation grep returns 0 non-comment matches in Endure surface
    Expected Result: SwapDebtDelegate + MoveDebtDelegate tests pass in Hardhat; both contracts vendored-only (zero references in Endure deploy surface)
    Failure Indicators: Any test failure not in SKIPPED.md; either delegate referenced from EndureDeployHelper or DeployLocal (would breach Hardhat-fixture-only isolation)
    Evidence: .sisyphus/evidence/task-35-{delegate,isolation}.log
  ```

  **Commit**: YES — `test(hardhat): vendor venus DelegateBorrowers fixtures green`

- [ ] 36. **Vendor Venus Swap (SwapRouter) Hardhat tests + fixtures green**

  **What to do**: Tests at `tests/hardhat/Swap/`. Fixtures deploy `SwapRouter`. Hardhat-fixture-only. Run `pnpm hardhat test --grep "Swap"` → green.

  **Recommended Agent Profile**: `unspecified-high`
  **Parallelization**: YES; Wave 4; blocks T39; blocked by T24, T2, T25b.
  **References**: spec line 656.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "Swap"` exits 0; no SwapRouter references in Endure surface

  **QA Scenarios**:

  ```
  Scenario: Swap tests pass
    Tool: Bash
    Preconditions: T2, T24 done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "Swap" 2>&1 | tee .sisyphus/evidence/task-36-swap.log
      2. Run: grep -r "SwapRouter" packages/contracts/test/endure/ packages/contracts/test/helper/EndureDeployHelper.sol 2>&1 | tee .sisyphus/evidence/task-36-isolation.log
      3. Assert: hardhat test exit 0; isolation grep returns 0 non-comment matches in Endure surface
    Expected Result: SwapRouter tests pass in Hardhat; SwapRouter never deployed in Endure's Foundry/Anvil deployment
    Failure Indicators: Any test failure not in SKIPPED.md; SwapRouter referenced from Endure deploy surface
    Evidence: .sisyphus/evidence/task-36-{swap,isolation}.log
  ```

  **Commit**: YES — `test(hardhat): vendor venus swap fixtures green`

- [ ] 37. **Vendor Venus Lens + Utils + Admin Hardhat tests; skip BNB-specific (VBNB + VBNBAdmin) without authoring new fixtures**

  **What to do**: Tests at `tests/hardhat/Lens/`, `tests/hardhat/Utils/`, `tests/hardhat/Admin/`. Use vendored upstream Venus deploy scripts and fixtures from `packages/contracts/deploy/` (vendored in T4) — DO NOT author new Endure-specific fixtures. Run `pnpm hardhat test --grep "Lens|Utils|Admin"` → green for all subsystems EXCEPT BNB-specific tests. **VBNB + VBNBAdmin handling**: per Bittensor irrelevance, both go to `tests/hardhat/SKIPPED.md` (added in T38) with rationale "BNB-irrelevant on Bittensor; vendored byte-identical for Stance B but NOT exercised in local Hardhat fixtures." This is a vendor-and-skip operation, not a fixture-authoring task.

  **Must NOT do**: Author new Endure-side fixtures or "spin up" Bittensor-specific test infrastructure for VBNB/VBNBAdmin — they are skipped, not adapted. Wave 4 is "vendor + adapt only if needed", NOT "author new test infrastructure."

  **Recommended Agent Profile**: `unspecified-high`
  **Parallelization**: YES; Wave 4; blocks T39; blocked by T24, T2, T25b.
  **References**: spec lines 657–660.

  **Acceptance Criteria**:
  - [ ] `pnpm hardhat test --grep "Lens|Utils|Admin"` exits 0 (or with skips documented)
  - [ ] If VBNBAdmin skipped: rationale in SKIPPED.md

  **QA Scenarios**:

  ```
  Scenario: Lens/Utils/Admin tests pass (or skipped+documented)
    Tool: Bash
    Preconditions: T2, T24 done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test --grep "Lens|Utils|Admin" 2>&1 | tee .sisyphus/evidence/task-37-lensutilsadmin.log
      2. Assert: hardhat test exit 0
      3. If VBNBAdmin skipped: assert SKIPPED.md (T38) contains an entry for it with rationale
      4. Assert: at minimum, Lens (RewardLens) + Utils (CheckpointView) tests run; Admin may be partially skipped
    Expected Result: All Lens + Utils tests pass; Admin tests pass OR documented in SKIPPED.md (e.g., VBNBAdmin if BNB-specific assumptions unfixable)
    Failure Indicators: Any non-Admin test fails; Admin test skipped without SKIPPED.md entry; exit non-zero
    Evidence: .sisyphus/evidence/task-37-lensutilsadmin.log
  ```

  **Commit**: YES — `test(hardhat): vendor venus lens/utils/admin fixtures green`

- [ ] 38. **Author `tests/hardhat/SKIPPED.md` + add CI verifier matching `it.skip` invocations**

  **What to do**:
  - Create `packages/contracts/tests/hardhat/SKIPPED.md` listing every test that's `it.skip`-ped or describe-skipped, with rationale per spec lines 661–667
  - Required entries:
    - All `tests/hardhat/Fork/**` (already not vendored from T3 — list as "not vendored, mainnet-fork dependency")
    - `VBNB` tests (any test under `tests/hardhat/` that exercises `VBNB.sol`) — rationale: "BNB-irrelevant on Bittensor; vendored byte-identical for Stance B but not exercised in local Hardhat network"
    - `VBNBAdmin` tests (per T37) — same rationale as VBNB
    - Any other test skipped during T26–T37 with a documented rationale
  - Add a script `scripts/check-hardhat-skips.sh` that:
    - Greps all `tests/hardhat/**/*.ts` for `it.skip`, `describe.skip`, `xit`, `xdescribe`
    - Compares against `tests/hardhat/SKIPPED.md` table
    - Fails CI if any skip is undocumented
  - Wire into CI's `contracts-hardhat-test` job (T39)

  **Must NOT do**: Skip a test without a SKIPPED.md row (CI will catch it).

  **Recommended Agent Profile**: `quick` — Doc + small script
  **Parallelization**: YES; Wave 4 closer
  **Blocks**: T39
  **Blocked By**: T26–T37

  **References**: spec lines 661–667

  **Acceptance Criteria**:
  - [ ] `tests/hardhat/SKIPPED.md` exists with at least Fork/ entry
  - [ ] `scripts/check-hardhat-skips.sh` exists, executable
  - [ ] Running it with no undocumented skips exits 0; with simulated undocumented skip exits 1

  **QA Scenarios**:

  ```
  Scenario: Skip-list verifier enforces documentation
    Tool: Bash
    Preconditions: T26–T37 done
    Steps:
      1. Run: bash scripts/check-hardhat-skips.sh 2>&1 | tee .sisyphus/evidence/task-38-skipcheck.log
      2. Add a temporary `it.skip` to a test, rerun, assert exit 1, remove the temporary
    Expected Result: Verifier enforces 1:1
    Evidence: .sisyphus/evidence/task-38-skipcheck.log
  ```

  **Evidence to Capture**: `.sisyphus/evidence/task-38-skipcheck.log`

  **Commit**: YES — `docs(test): add hardhat skip list + ci verifier`

- [ ] 39. **Add CI job `contracts-hardhat-test` (gate: `hardhat test` exits 0)**

  **What to do**:
  - Add CI job `contracts-hardhat-test` to `.github/workflows/ci.yml` that:
    - Depends on `contracts-hardhat-build` (T6)
    - Runs `pnpm --filter @endure/contracts hardhat test`
    - Then runs `bash scripts/check-hardhat-skips.sh`
    - Caches `cache_hardhat/` and `artifacts/` from T6
  - Job runs in parallel with `contracts-test` (Foundry)
  - Push to a CI-test branch; verify job appears and passes

  **Must NOT do**: Make this a hard gate for `contracts-test` (Foundry path independent).

  **Recommended Agent Profile**: `quick` — YAML edit
  **Parallelization**: NO — final Wave 4 gate
  **Blocks**: T44 (e2e-smoke wiring depends on Hardhat green proof)
  **Blocked By**: T26–T38

  **References**: spec line 694; existing `.github/workflows/ci.yml` structure

  **Acceptance Criteria**:
  - [ ] CI yaml contains `contracts-hardhat-test` job
  - [ ] On a CI-test push, the job concludes "success"

  **QA Scenarios**:

  ```
  Scenario: Hardhat test CI job runs and passes
    Tool: Bash
    Preconditions: T38 done
    Steps:
      1. Run: pnpm --filter @endure/contracts hardhat test 2>&1 | tail -30 | tee .sisyphus/evidence/task-39-hardhat-test.log
      2. Push to ci-test-task-39, run gh run view, capture conclusion
    Expected Result: All hardhat tests green; CI job concludes success
    Failure Indicators: Any failure not in SKIPPED.md
    Evidence: .sisyphus/evidence/task-39-hardhat-test.log
  ```

  **Evidence to Capture**: `.sisyphus/evidence/task-39-hardhat-test.log`

  **Commit**: YES — `ci(contracts): add hardhat test gate`

---

### Wave 5 — CI + smoke + gas snapshot (Chunk 5a)

- [ ] 40. **Repoint `stance-b-audit` job: `.upstream-sha` → `6400a067`; audit covers `src/venus-staging/**`**

  **What to do**:
  - Update `packages/contracts/.upstream-sha`: change content from `8d5fb1107babf7935cfabc2f6ecdb1722547f085` to `6400a067114a101bd3bebfca2a4bd06480e84831`
  - Update the inline Stance B audit logic in `.github/workflows/ci.yml` (job `stance-b-audit`):
    - Clone target: change from Moonwell (`solace-fi/moonwell`) to `VenusProtocol/venus-protocol` (verify exact upstream URL/repo name)
    - Audit scope: `packages/contracts/src/venus-staging/**` byte-compared to `<venus>/contracts/**` (path-mapped: `src/venus-staging/Foo.sol` ↔ `<venus>/contracts/Foo.sol`)
    - Also audit `packages/contracts/src/test-helpers/venus/**` against `<venus>/contracts/test/**`
    - Also audit each `lib/venusprotocol-*/contracts/**` against its own pinned commit (record commits in `FORK_MANIFEST.md`)
    - For files under `src/endure/`: SKIP byte audit; instead run a forbidden-pattern scan for Moonwell-only types (`MToken`, `MErc20`, `MErc20Delegator`, `mWell`, `WELL`, `xWELL`)
  - **MANDATORY**: Extract the Stance B audit logic from `.github/workflows/ci.yml` inline script into a new `scripts/check-stance-b.sh` that is locally runnable AND invoked by the CI yaml job (CI yaml calls the script; script is the single source of truth). This is required so T46 and T49 QA scenarios can invoke it directly.
  - The new `scripts/check-stance-b.sh` must:
    - Accept `UPSTREAM_SHA` from `packages/contracts/.upstream-sha` (or env var override)
    - Clone `VenusProtocol/venus-protocol` at that SHA into a temp dir
    - **Main audit (Venus contracts)**: SHA256-compare `packages/contracts/src/venus-staging/**/*.sol` against `<venus>/contracts/**/*.sol` (path-mapped). **Glob MUST exclude `src/endure/**` AND `src/test-helpers/**`** — they have their own dedicated audit passes. Without these exclusions, `src/test-helpers/venus/MockToken.sol` would be searched for at `<venus>/contracts/test-helpers/venus/MockToken.sol` (which doesn't exist) and falsely reported as orphan.
    - Post-T46 (mass-move complete): main glob becomes `packages/contracts/src/**/*.sol` excluding `src/endure/**` AND `src/test-helpers/**`, compared against `<venus>/contracts/**/*.sol` directly
    - **Test-helpers audit (separate pass)**: SHA256-compare `packages/contracts/src/test-helpers/venus/**/*.sol` against `<venus>/contracts/test/**/*.sol` (note: upstream path is `contracts/test/`, NOT `contracts/test-helpers/`)
    - **Dependencies audit (Approach A — primary)**: Run `npm install` in the cloned Venus repo at `6400a067`, then SHA256-compare `<cloned>/node_modules/@venusprotocol/<pkg>/contracts/**` against `lib/venusprotocol-<pkg>/contracts/**` for each of 5 packages. This matches how Stage A actually vendored these files.
    - **Dependencies audit (Approach B — supplementary, informational only)**: Per package, if FORK_MANIFEST Section 6.7 has a non-N/A standalone SHA, optionally clone the standalone repo at that SHA and byte-compare. Report mismatches as INFO (not FAIL). The hard gate is Approach A.
    - **Endure-authored files audit**: For files under `src/endure/`: SKIP byte audit; instead grep for Moonwell-only types (`MToken`, `MErc20`, `MErc20Delegator`, `mWell`, `WELL`, `xWELL`). Fail on any non-comment match.
    - Exit 0 on full success; exit 1 on any SHA mismatch or orphan file (Approach A); INFO-only for Approach B
    - Print a summary table of audited file counts per scope (Venus contracts, test-helpers, deps via Approach A, endure-authored)
  - Verify: locally clone Venus at the pin, run `bash scripts/check-stance-b.sh`, expect zero SHA mismatches and exit 0

  **Must NOT do**:
  - Do NOT delete the Moonwell entries in `FORK_MANIFEST.md` yet — Chunk 5b handles that
  - Do NOT change the audit failure mode (exit 1 on mismatch)
  - Do NOT skip dependency package audits

  **Recommended Agent Profile**: `unspecified-high` — Multiple repo references, careful path mapping
  **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES within Wave 5
  - **Parallel Group**: Wave 5 (with T41–T44)
  - **Blocks**: T45 (mass-move depends on audit being correctly scoped)
  - **Blocked By**: T39, T25c (FORK_MANIFEST Section 6.7 must contain the 5 dependency SHAs the audit script consumes)

  **References**:

  **Pattern References**:
  - Existing `.github/workflows/ci.yml` `stance-b-audit` job inline script
  - `packages/contracts/.upstream-sha` — current Moonwell pin

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:670-686` — Stance B audit update spec
  - Venus pin: `6400a067114a101bd3bebfca2a4bd06480e84831`
  - Venus repo: `https://github.com/VenusProtocol/venus-protocol`

  **WHY Each Reference Matters**:
  - The audit is the byte-identity guarantee that distinguishes Stance B from Stance A; getting the path mapping wrong creates a false-green CI that allows drift

  **Acceptance Criteria**:
  - [ ] `.upstream-sha` content == `6400a067114a101bd3bebfca2a4bd06480e84831`
  - [ ] `scripts/check-stance-b.sh` EXISTS, is executable, and contains the full audit logic (NOT optional — required for T46/T49 to be runnable)
  - [ ] `.github/workflows/ci.yml` `stance-b-audit` job invokes `bash scripts/check-stance-b.sh` (script is the single source of truth)
  - [ ] Audit scope includes `src/venus-staging/**` AND `src/test-helpers/venus/**` AND each `lib/venusprotocol-*/contracts/**`
  - [ ] `bash scripts/check-stance-b.sh` exits 0 locally; zero SHA mismatches reported

  **QA Scenarios**:

  ```
  Scenario: Stance B script extracted, executable, and audit passes
    Tool: Bash
    Preconditions: T39 done
    Steps:
      1. Run: cat packages/contracts/.upstream-sha | tee .sisyphus/evidence/task-40-pin.log
      2. Run: ls -l scripts/check-stance-b.sh | tee .sisyphus/evidence/task-40-script-exists.log
      3. Run: bash scripts/check-stance-b.sh 2>&1 | tee .sisyphus/evidence/task-40-audit.log
      4. Assert: pin matches `6400a067114a101bd3bebfca2a4bd06480e84831`; script file exists and is executable; audit exits 0
    Expected Result: Script extracted, audit clean
    Failure Indicators: Script missing or non-executable, wrong pin, any SHA mismatch, missing scope
    Evidence: .sisyphus/evidence/task-40-{pin,script-exists,audit}.log

  Scenario: CI yaml invokes the script (single source of truth)
    Tool: Bash
    Preconditions: T40 implementation done
    Steps:
      1. Run: grep "check-stance-b.sh" .github/workflows/ci.yml | tee .sisyphus/evidence/task-40-ci-invokes.log
      2. Assert: at least one line in CI yaml invokes the script
    Expected Result: CI yaml uses the script
    Failure Indicators: CI yaml retains inline duplicate logic
    Evidence: .sisyphus/evidence/task-40-ci-invokes.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-40-pin.log`
  - [ ] `.sisyphus/evidence/task-40-audit.log`

  **Commit**: YES
  - Message: `ci(stance-b): extract audit script + repoint to venus pin 6400a067`
  - Files: `packages/contracts/.upstream-sha`, `.github/workflows/ci.yml`, **`scripts/check-stance-b.sh` (new, mandatory)**
  - Evidence script existence + executability captured

- [ ] 41. **Rewrite `scripts/e2e-smoke.sh` for Venus addresses + events + direct vToken liquidation**

  **What to do**:
  - Rewrite `scripts/e2e-smoke.sh`:
    - Read addresses from `packages/deploy/addresses.json` (per T12 schema): `unitroller`, `vWTAO`, `vAlpha30`, `wtao`, `mockAlpha30`, `resilientOracle`
    - Use `cast` to: mint mock alpha → approve vAlpha30 → enterMarkets → supply → borrow vWTAO → repay → redeem
    - Assert each step's effect via `cast call` on `Comptroller.markets`, `vToken.balanceOf`, etc.
    - Trigger price drop: call `MockResilientOracle.setUnderlyingPrice(vAlpha30, lower_price)` via `cast send`
    - Direct liquidation: as a different EOA, call `vWTAO.liquidateBorrow(borrower, repayAmount, vAlpha30)` — assert success
    - Check for Venus's `Failure(uint256, uint256, uint256)` event (NOT Moonwell's signature) on any expected-soft-fail call
  - Print structured log; exit 0 on success, non-zero on any assertion failure

  **Must NOT do**:
  - Do NOT use Moonwell event signatures (Failure/MarketEntered/etc. differ slightly)
  - Do NOT use external Liquidator
  - Do NOT depend on Hardhat deployment state
  - Do NOT hardcode addresses — always read from `addresses.json`

  **Recommended Agent Profile**: `unspecified-high` — Bash + cast scripting with Venus event awareness
  **Parallelization**: YES within Wave 5
  **Blocks**: T44
  **Blocked By**: T39

  **References**:

  **Pattern References**:
  - `scripts/e2e-smoke.sh` (Phase 0 Moonwell version) — script structure
  - `packages/deploy/addresses.json` (T12 sample output)

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:578-583` — Chunk 5a smoke updates
  - Venus event signatures: `src/venus-staging/Comptroller/ComptrollerStorage.sol::Failure`

  **WHY Each Reference Matters**:
  - Event signature mismatch causes silent test passes (cast filter returns nothing → no failures detected)

  **Acceptance Criteria**:
  - [ ] On a fresh Anvil + Venus deploy: `bash scripts/e2e-smoke.sh` exits 0
  - [ ] Script exercises mint, approve, enterMarkets, supply, borrow, repay, redeem, liquidate
  - [ ] Venus's `Failure` event signature is referenced (not Moonwell's)

  **QA Scenarios**:

  ```
  Scenario: e2e-smoke succeeds against Venus deploy
    Tool: Bash
    Preconditions: T12 (deploy script) done; T40 (audit) done
    Steps:
      1. Run: anvil --port 8545 > /tmp/anvil.log 2>&1 &
      2. Sleep 2
      3. Run: forge script packages/deploy/src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 2>&1 | tee .sisyphus/evidence/task-41-deploy.log
      4. Run: bash scripts/e2e-smoke.sh 2>&1 | tee .sisyphus/evidence/task-41-smoke.log
      5. Kill anvil
      6. Assert: smoke exits 0
    Expected Result: All 8 lifecycle steps + liquidation succeed
    Failure Indicators: Any cast call revert, missing event emission, exit non-zero
    Evidence: .sisyphus/evidence/task-41-{deploy,smoke}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-41-deploy.log`
  - [ ] `.sisyphus/evidence/task-41-smoke.log`

  **Commit**: YES — `chore(scripts): rewrite e2e-smoke for venus`

- [ ] 42. **Update `scripts/check-forbidden-patterns.sh` to scan for Moonwell remnants (warning-only during dual-vendor; hard-gate post-T46/T46b)**

  **What to do**:
  - Update `scripts/check-forbidden-patterns.sh` with TWO MODES controlled by an env var (single source of truth — no contradiction between local + CI behavior):
    - Patterns to add: `MToken`, `MErc20`, `MErc20Delegator`, `MWethDelegate`, `mWell`, `\bWELL\b`, `xWELL`
    - Scope: scan `src/` excluding `src/venus-staging/` (during staging) and excluding comments + `FORK_MANIFEST.md` + `UPSTREAM.md`
    - Post-T46/T46b: scope becomes `src/` excluding `src/endure/` (Venus does NOT use `M*` prefix, so legitimate Venus files won't match)
    - **WARNING-ONLY MODE (default during dual-vendor period)**: Script prints findings to stderr with `[WARN]` prefix, prints summary count, exits 0 (does NOT fail). Activated by absence of env var `STRICT=1` (default behavior).
    - **STRICT MODE (post-T46/T46b)**: Same script, same scope, same patterns — but with `STRICT=1` env var, exits 1 on any match outside allowed paths.
    - This task lands the script in WARNING-ONLY default mode. T46 (Commit B1) updates the CI yaml step to set `STRICT=1` (since by then Moonwell is being actively deleted).
  - Local invocation during dual-vendor: `bash scripts/check-forbidden-patterns.sh` exits 0 (warning-only); prints findings if any
  - Local invocation post-T46: `STRICT=1 bash scripts/check-forbidden-patterns.sh` exits 1 if any Moonwell remnant found

  **Must NOT do**:
  - Do NOT scan `FORK_MANIFEST.md` or `UPSTREAM.md` (legitimate references)
  - Do NOT scan comments (a `// formerly MToken` reference is OK)
  - Do NOT enable STRICT mode in CI yet (will fail until Chunk 5b deletion lands). The `STRICT=1` flag flip happens in T46 (Commit B1) when Moonwell is being deleted in the same PR.
  - Do NOT use `continue-on-error: true` in CI yaml — the env var pattern is cleaner (script behavior matches expectations regardless of caller)

  **Recommended Agent Profile**: `quick` — Pattern list + scope tweak
  **Parallelization**: YES within Wave 5
  **Blocks**: nothing critical (it's a future-state scan)
  **Blocked By**: T39

  **References**:

  **Pattern References**: existing `scripts/check-forbidden-patterns.sh`
  **External References**: `docs/briefs/phase-0.5-venus-rebase-spec.md:577` — scope statement; line 695 — pattern list

  **WHY Each Reference Matters**: Catches Moonwell remnants that would otherwise hide in Endure-authored files post-rebase.

  **Acceptance Criteria**:
  - [ ] Script updated with all 7 patterns
  - [ ] Script supports `STRICT` env var: absence → warning-only (exit 0, prints findings); `STRICT=1` → hard-gate (exit 1 on any match)
  - [ ] Default invocation (`bash scripts/check-forbidden-patterns.sh`) exits 0 during dual-vendor period (warning mode), prints WARN lines for any current Moonwell-side matches
  - [ ] Strict invocation (`STRICT=1 bash scripts/check-forbidden-patterns.sh`) exits non-zero on ANY match outside allowed paths
  - [ ] CI yaml `forbidden-patterns` job invokes the script WITHOUT `STRICT=1` until T46 (default warning-only behavior)

  **QA Scenarios**:

  ```
  Scenario: Default mode (warning-only) exits 0 even when Moonwell present
    Tool: Bash
    Preconditions: T39 done; Moonwell still in repo (dual-vendor period)
    Steps:
      1. Run: grep -E "(MToken|MErc20|mWell|WELL|xWELL)" scripts/check-forbidden-patterns.sh | tee .sisyphus/evidence/task-42-patterns.log
      2. Run: bash scripts/check-forbidden-patterns.sh 2>&1; echo "exit:$?" | tee .sisyphus/evidence/task-42-default-mode.log
      3. Assert: all 7 patterns present in script source; default-mode exit code is 0; log contains [WARN] lines for Moonwell findings
    Expected Result: Default mode exits 0 with WARN output (proves warning-only behavior)
    Failure Indicators: Missing patterns; default mode exits non-zero (would fail CI prematurely)
    Evidence: .sisyphus/evidence/task-42-{patterns,default-mode}.log

  Scenario: Strict mode exits non-zero when Moonwell present
    Tool: Bash
    Preconditions: T42 implementation done; Moonwell still in repo
    Steps:
      1. Run: STRICT=1 bash scripts/check-forbidden-patterns.sh 2>&1; echo "exit:$?" | tee .sisyphus/evidence/task-42-strict-mode.log
      2. Assert: exit code is non-zero (proves strict mode would fail CI if Moonwell remnants remained)
    Expected Result: Strict mode exits 1 (proves the post-T46 behavior works)
    Failure Indicators: Strict mode exits 0 (script doesn't enforce strict gate)
    Evidence: .sisyphus/evidence/task-42-strict-mode.log

  Scenario: CI yaml invokes script without STRICT (default mode preserved)
    Tool: Bash
    Steps:
      1. Run: grep -A 3 "check-forbidden-patterns" .github/workflows/ci.yml | tee .sisyphus/evidence/task-42-ci.log
      2. Assert: invocation does NOT pass `STRICT=1` (will be added by T46)
    Expected Result: CI uses default warning-only mode through the dual-vendor period
    Failure Indicators: STRICT=1 set prematurely (would fail CI on every dual-vendor build)
    Evidence: .sisyphus/evidence/task-42-ci.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-42-patterns.log`
  - [ ] `.sisyphus/evidence/task-42-run.log`

  **Commit**: YES — `chore(scripts): update forbidden-patterns for moonwell remnants`

- [ ] 43. **Regenerate `.gas-snapshot` baseline + update tolerance commentary**

  **What to do**:
  - Delete current `packages/contracts/.gas-snapshot` (or the path Phase 0 uses — confirm via `find . -name ".gas-snapshot"`)
  - Run `forge snapshot --root packages/contracts` to regenerate against the Venus chassis
  - Inspect the diff: gas costs will change substantially (Diamond routing has delegatecall overhead vs Moonwell's direct dispatch)
  - Update `scripts/gas-snapshot-check.sh` if tolerance commentary needs adjustment for the new baseline
  - Document the rebaseline in a brief commit message body explaining "Venus chassis introduces Diamond delegatecall overhead; previous Moonwell baseline obsolete"
  - Verify: `bash scripts/gas-snapshot-check.sh` exits 0 against the fresh baseline

  **Must NOT do**:
  - Do NOT regenerate piecemeal — full rebaseline in one commit
  - Do NOT loosen tolerance to mask real regressions; keep tolerance proportional to Phase 0's

  **Recommended Agent Profile**: `quick` — Snapshot regen + tolerance review
  **Parallelization**: YES within Wave 5
  **Blocks**: T44
  **Blocked By**: T39

  **References**:

  **Pattern References**: `scripts/gas-snapshot-check.sh`, existing `.gas-snapshot` location

  **External References**: `docs/briefs/phase-0.5-venus-rebase-spec.md:584` — snapshot rebaseline mandate

  **WHY**: Gas costs change with chassis swap; without rebaseline, every CI run fails on the gas job.

  **Acceptance Criteria**:
  - [ ] `.gas-snapshot` regenerated and committed
  - [ ] `bash scripts/gas-snapshot-check.sh` exits 0
  - [ ] Tolerance commentary in script reflects Diamond overhead reality

  **QA Scenarios**:

  ```
  Scenario: Gas snapshot rebaselined
    Tool: Bash
    Preconditions: T39 done
    Steps:
      1. Run: forge snapshot --root packages/contracts 2>&1 | tee .sisyphus/evidence/task-43-snapshot.log
      2. Run: bash scripts/gas-snapshot-check.sh 2>&1 | tee .sisyphus/evidence/task-43-check.log
      3. Assert: snapshot file updated; check exits 0
    Expected Result: Fresh baseline accepted
    Failure Indicators: Check fails against own baseline (script bug), or test count regression
    Evidence: .sisyphus/evidence/task-43-{snapshot,check}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-43-snapshot.log`
  - [ ] `.sisyphus/evidence/task-43-check.log`

  **Commit**: YES — `chore(snapshot): rebaseline gas-snapshot for venus`

- [ ] 44. **Wire `e2e-smoke` CI job to new script + Venus deploy**

  **What to do**:
  - Update `.github/workflows/ci.yml`'s `e2e-smoke` job to:
    - Use the rewritten `scripts/e2e-smoke.sh` from T41
    - Call `forge script packages/deploy/src/DeployLocal.s.sol` (T12) for setup
    - Add a step that confirms `addresses.json` is generated correctly before invoking smoke
  - Push to a CI-test branch; verify the job exits 0

  **Must NOT do**: Reference the old Moonwell deploy script path.

  **Recommended Agent Profile**: `quick` — YAML edit
  **Parallelization**: NO — Wave 5 closer
  **Blocks**: T45
  **Blocked By**: T41, T43

  **References**: `.github/workflows/ci.yml` existing `e2e-smoke` job; `docs/briefs/phase-0.5-venus-rebase-spec.md:578`.

  **WHY**: Closes the loop on Chunk 5a — proves the full Venus deploy + smoke pipeline works end-to-end in CI before the high-risk Chunk 5b.

  **Acceptance Criteria**:
  - [ ] CI yaml `e2e-smoke` job uses new script + Venus deploy
  - [ ] CI-test push: job concludes "success"
  - [ ] All Wave 5 outputs (Stance B audit pass, e2e-smoke pass, gas snapshot pass, forbidden-patterns warning) hold

  **QA Scenarios**:

  ```
  Scenario: Full CI suite green at end of Chunk 5a (job-level verification)
    Tool: Bash + gh CLI
    Preconditions: T40, T41, T42, T43 done; gh CLI authenticated
    Steps:
      1. Run: git push origin HEAD:ci-test-task-44
      2. Wait for the workflow run to start: sleep 15
      3. Capture the run ID: RUN_ID=$(gh run list --branch ci-test-task-44 --workflow ci.yml --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$RUN_ID" | tee .sisyphus/evidence/task-44-runid.log
      4. Wait for completion (block until the run finishes): gh run watch $RUN_ID --exit-status 2>&1 | tee .sisyphus/evidence/task-44-watch.log
      5. Capture per-job status: gh run view $RUN_ID --json jobs --jq '.jobs[] | {name: .name, conclusion: .conclusion}' > .sisyphus/evidence/task-44-jobs.json
      6. Assert each REQUIRED job in jobs.json has `conclusion == "success"`. Required job names match the actual `.github/workflows/ci.yml`: `contracts-build`, `contracts-test` (which runs both `forge test` AND `scripts/gas-snapshot-check.sh` as steps within itself — gas-snapshot-check is NOT a separate job), `contracts-hardhat-build`, `contracts-hardhat-test`, `stance-b-audit`, `e2e-smoke`, `forbidden-patterns`, `pnpm-workspace`. Verify exact job names by running: jq -r '.jobs[].name' .sisyphus/evidence/task-44-jobs.json | sort > .sisyphus/evidence/task-44-job-names.log
      7. For the `forbidden-patterns` job: it must show `conclusion == "success"` because T42 implements warning-only mode (script exits 0 by default during dual-vendor period); CI yaml does NOT pass STRICT=1 until T46
      8. For the `contracts-test` job: success implies BOTH `forge test` AND `gas-snapshot-check.sh` (step within it) passed
    Expected Result: All 8 jobs (job-level data confirmed) report `conclusion == "success"`; gas snapshot enforced via `contracts-test` step (not separate job); forbidden-patterns succeeds in warning-only mode
    Failure Indicators: Any job conclusion != "success"; missing required job from the list; gas-snapshot-check step failure within contracts-test (visible in the job log)
    Evidence: .sisyphus/evidence/task-44-{runid,watch,jobs,job-names}.log/.json

  Scenario: Local dry-run validation (alternative to gh push) for tasks where push permissions aren't available
    Tool: Bash
    Preconditions: act installed (or gh CLI authenticated)
    Steps:
      1. Run locally what each CI job runs:
         - `forge build --root packages/contracts` (mirrors contracts-build)
         - `forge test --root packages/contracts -v && bash scripts/gas-snapshot-check.sh` (mirrors contracts-test)
         - `pnpm --filter @endure/contracts hardhat compile` (mirrors contracts-hardhat-build)
         - `pnpm --filter @endure/contracts hardhat test` (mirrors contracts-hardhat-test)
         - `bash scripts/check-stance-b.sh` (mirrors stance-b-audit)
         - `bash scripts/e2e-smoke.sh` (after anvil + deploy; mirrors e2e-smoke)
         - `bash scripts/check-forbidden-patterns.sh` (mirrors forbidden-patterns; warning-only default)
      2. Capture each command's exit code
      3. Save to .sisyphus/evidence/task-44-local.log
      4. Assert: every command exits 0
    Expected Result: All 7 local equivalents exit 0
    Failure Indicators: Any non-zero exit
    Evidence: .sisyphus/evidence/task-44-local.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-44-runid.log`
  - [ ] `.sisyphus/evidence/task-44-watch.log`
  - [ ] `.sisyphus/evidence/task-44-jobs.json`
  - [ ] `.sisyphus/evidence/task-44-job-names.log`
  - [ ] `.sisyphus/evidence/task-44-local.log`

  **Commit**: YES — `ci(contracts): wire e2e-smoke for venus deploy`

---

### Wave 6 — Mass-move + delete-Moonwell (Chunk 5b) — THREE ATOMIC COMMITS (per Metis split)

> **CRITICAL**: This wave produces THREE atomic commits in strict order (Metis-recommended split of original Commit B for reviewability):
> - **Commit A (T45)** — delete Moonwell chassis (CI RED expected)
> - **Commit B1 (T46)** — structural mass-move + import path rewrites + Hardhat config flip + minimal FORK_MANIFEST update (CI may stay RED — old Moonwell helper still present, fails compile)
> - **Commit B2 (T46b)** — dual-helper teardown: delete old Moonwell helper, rename Venus helper back to canonical name, bulk struct rename, naming cleanup (CI restored to GREEN)
>
> Reverting B2 returns to a state where the move is done but naming is split (workable for debugging). Reverting B1+B2 returns to pre-Chunk-5b. This pattern is per spec line 587–593 with Metis-suggested commit-granularity refinement.

- [ ] 45. **Commit A — Delete all Moonwell `.sol` + `src/rewards/` + Moonwell `lib/` + Moonwell `proposals/` + update FORK_MANIFEST.md**

  **What to do**:
  - Delete every `.sol` file under `packages/contracts/src/` that does NOT start with `venus-staging/` or `endure/`. Specifically: `Comptroller.sol`, `ComptrollerInterface.sol`, `ComptrollerStorage.sol`, `MToken.sol`, `MTokenInterfaces.sol`, `MErc20.sol`, `MErc20Delegate.sol`, `MErc20Delegator.sol`, `MLikeDelegate.sol`, `MWethDelegate.sol`, `MWethOwnerWrapper.sol`, `OEVProtocolFeeRedeemer.sol`, `Recovery.sol`, `Unitroller.sol`, `WethUnwrapper.sol`, `CarefulMath.sol`, `EIP20Interface.sol`, `EIP20NonStandardInterface.sol`, `Exponential.sol`, `ExponentialNoError.sol`, `SafeMath.sol`, `TokenErrorReporter.sol`
  - Delete directories: `src/rewards/`, `src/cypher/`, `src/governance/`, `src/interfaces/`, `src/irm/`, `src/market/`, `src/oracles/`, `src/router/`, `src/utils/`, `src/views/` (all Moonwell). KEEP: `src/venus-staging/`, `src/endure/`, `src/test-helpers/venus/`, `src/4626` (verify if used; delete if Moonwell-only)
  - Delete `src/endure/MockPriceOracle.sol` (Moonwell-only oracle mock; replaced by `MockResilientOracle.sol`)
  - Delete Moonwell-specific `lib/` entries: `lib/solmate/`, `lib/zelt/`, any others not used by Venus (VERIFY by checking remappings.txt — anything not referenced by Venus or OZ goes)
  - Delete Moonwell-specific files in `script/`: `DeployFaucetToken.s.sol`, `DeployJRM.s.sol`, `DeployMarketAddChecker.s.sol`, `DeployStaticPriceFeed.s.sol`, `script/rewards/`, `script/templates/` if Moonwell-specific
  - Delete `proposals/` entirely if Moonwell-specific (verify)
  - Delete Phase 0 Moonwell tests: `test/endure/MockAlpha.t.sol` keeps (already ported in T18); other tests covered by ports
  - Update `FORK_MANIFEST.md`: ARCHIVE the entirety of Sections 1–5 (Moonwell deleted/modified/added/unchanged/deviation entries) under a new collapsed header `## Phase 0 Historical Audit Trail (archival; Moonwell chassis deleted in Chunk 5b Commit A)`. Keep them in the file for historical reference but clearly demarcated as no-longer-applicable. Section 6 (Stage A Venus vendoring) and 6.7 (dependency SHAs from T25c) remain authoritative for the current state.
  - DO NOT do selective per-line deletion within Section 5 — wholesale archive of Sections 1–5 is required to avoid leaving Sections 1–4 orphaned (they describe Moonwell files that no longer exist)
  - Commit message: `feat(contracts): delete moonwell chassis (CI RED EXPECTED on this commit)`
  - **DO NOT** push as a standalone commit to `phase-0.5-venus-rebase`; instead push T45+T46 as a single PR with both commits visible in history

  **Must NOT do**:
  - Do NOT delete `src/venus-staging/`, `src/endure/`, `src/test-helpers/venus/`
  - Do NOT touch `lib/openzeppelin-*`, `lib/forge-std`, `lib/venusprotocol-*`
  - Do NOT bundle delete and move into one commit (atomicity violation)
  - Do NOT push to `phase-0.5-venus-rebase` until T46 commit B is also ready

  **Recommended Agent Profile**: `unspecified-high` — Large mechanical deletion with careful inclusion list
  **Parallelization**: NO — sequential
  **Blocks**: T46
  **Blocked By**: T44

  **References**:

  **Pattern References**:
  - `packages/contracts/src/` current layout listing
  - Spec lines 587–590 (Commit A scope)
  - `packages/contracts/FORK_MANIFEST.md` (current Moonwell deviation entries)

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:316-326` — penultimate commit description

  **WHY**: Atomic split ensures Commit A is `git revert`-safe (single commit reverts cleanly to pre-delete state). Bundling delete + move makes revert risky.

  **Acceptance Criteria**:
  - [ ] All Moonwell `.sol` files removed from `src/` (excluding `venus-staging/`, `endure/`, `test-helpers/venus/`)
  - [ ] `src/endure/MockPriceOracle.sol` removed
  - [ ] `src/endure/MockResilientOracle.sol` STILL PRESENT
  - [ ] `src/venus-staging/` STILL PRESENT (move happens in T46)
  - [ ] `forge build` is EXPECTED to FAIL on this commit (because Endure-authored code in `src/endure/` likely references Moonwell types — those references will be fixed in T46 import updates)
  - [ ] Commit message states "CI RED EXPECTED"

  **QA Scenarios**:

  ```
  Scenario: Moonwell chassis deleted; CI red as expected
    Tool: Bash
    Preconditions: T44 done; on a working tree separate from main branch
    Steps:
      1. Run: ls packages/contracts/src/Comptroller.sol packages/contracts/src/MToken.sol packages/contracts/src/endure/MockPriceOracle.sol 2>&1 | tee .sisyphus/evidence/task-45-moonwell-gone.log
      2. Run: ls packages/contracts/src/venus-staging/Comptroller/Diamond/Diamond.sol packages/contracts/src/endure/MockResilientOracle.sol 2>&1 | tee .sisyphus/evidence/task-45-venus-still.log
      3. Run: forge build --root packages/contracts 2>&1 | tail -10 | tee .sisyphus/evidence/task-45-build-red.log
      4. Assert: Moonwell ls returns "No such file"; Venus ls succeeds; build EXPECTED to fail
    Expected Result: Moonwell gone, Venus still here, build red
    Failure Indicators: Moonwell file still present, Venus accidentally deleted, build green (means deletion incomplete and Endure code didn't reference Moonwell — investigate)
    Evidence: .sisyphus/evidence/task-45-{moonwell-gone,venus-still,build-red}.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/task-45-moonwell-gone.log`
  - [ ] `.sisyphus/evidence/task-45-venus-still.log`
  - [ ] `.sisyphus/evidence/task-45-build-red.log`

  **Commit**: YES (Commit A of Chunk 5b)
  - Message: `feat(contracts): delete moonwell chassis (CI RED EXPECTED on this commit)`
  - Files: many deletions (use `git rm`)
  - Pre-commit: list of files to delete reviewed manually; build red is OK

- [ ] 46. **Commit B1 — `git mv src/venus-staging/* src/` + bulk import path rewrite + Hardhat paths.sources flip + audit script update + minimal FORK_MANIFEST update**

  **What to do**:
  - **PRECONDITION**: T5 already moved `src/venus-staging/test/` → `src/test-helpers/venus/` in Wave 1. Therefore `src/venus-staging/` at this point contains only the contracts subtrees (Comptroller/, Tokens/, InterestRateModels/, Lens/, Oracle/, VAIVault/, XVSVault/, VRTVault/, PegStability/, Prime/, Liquidator/, Swap/, DelegateBorrowers/, FlashLoan/, Admin/, Governance/, Utils/, external/, lib/) — NO `test/` subdir. This avoids the collision with Endure's existing `packages/contracts/test/` directory.
  - VERIFY pre-move: `ls packages/contracts/src/venus-staging/test 2>&1` should return "No such file or directory" (T5 moved it earlier; if not, T5 is incomplete and this task must HALT)
  - Run: `git mv packages/contracts/src/venus-staging/Comptroller packages/contracts/src/Comptroller && git mv ... ` (one mv per top-level subdir under `venus-staging/`)
  - After all mvs, `rmdir packages/contracts/src/venus-staging`
  - Bulk import-path rewrite across these directories (use `sed` or `ast-grep`):
    - `src/endure/**/*.sol`
    - `test/**/*.sol`
    - `tests/hardhat/**/*.ts`
    - `script/**/*.sol`
    - `deploy/**/*.ts`
    - `packages/deploy/src/**/*.sol`
  - Replacement: `@protocol/venus-staging/X/Y.sol` → `@protocol/X/Y.sol`; same for `import "../../src/venus-staging/...";` style relative imports
  - Update `scripts/check-stance-b.sh` (extracted in T40 — guaranteed present) path mapping: drop the `venus-staging/` prefix; audit now compares `src/Foo/Bar.sol` ↔ `<venus>/contracts/Foo/Bar.sol` directly. Also update the audit globs to exclude `src/test-helpers/**` from the main Venus-contracts pass (per Metis CRITICAL finding 6a — test-helpers have their own dedicated pass).
  - Update `packages/contracts/hardhat.config.ts` `paths.sources`: change from `"./src/venus-staging"` to `"./src"` (the comment T25b left explaining this transition is now actioned). Verify `pnpm hardhat compile` and `pnpm hardhat test` both still pass after the flip
  - **DUAL-HELPER TEARDOWN DEFERRED TO T46b (Commit B2)**: Do NOT delete the old `EndureDeployHelper.sol`, do NOT rename `EndureDeployHelperVenus.sol`, do NOT bulk-rename struct names in this commit. Those are T46b's responsibility. As a result, T46 (Commit B1) is expected to still have BOTH helpers present and tests still importing `EndureDeployHelperVenus`. CI may be RED after Commit B1 if the old Moonwell `EndureDeployHelper.sol` references types deleted in T45 — that's acceptable; T46b restores GREEN.
  - Update `.github/workflows/ci.yml` `forbidden-patterns` job step to set `STRICT=1` env var (per T42's contract — flip from warning-only to strict-gate mode now that Moonwell is being deleted in this same PR). Example: `run: STRICT=1 bash scripts/check-forbidden-patterns.sh`
  - Update `.github/workflows/ci.yml` Stance B job inline logic similarly
  - Update `FORK_MANIFEST.md` to a MINIMAL steady-state shape that is sufficient to make Stance B audit (T40) pass after the mass-move:
    - Update path mapping language: `src/venus-staging/Foo/Bar.sol` → `src/Foo/Bar.sol` and `src/venus-staging/test/X.sol` → `src/test-helpers/venus/X.sol`
    - Update Section 6 paths to reflect post-move layout
    - Confirm Section 6.7 dependency SHA table (from T25c) is still present and unchanged
    - Add a placeholder header for `## Documented deviations (steady-state)` with content `(none — verified by Stance B audit)` if applicable
    - **THIS TASK DOES THE MINIMUM REQUIRED FOR CI GREEN**. Full file-list regeneration + extensive section-rewrite is deferred to T49 to avoid bloating the Chunk 5b mass-move commit
  - Make explicit in the commit body: "FORK_MANIFEST minimally updated to make Stance B pass post-move; T49 expands to full 6-section spec-compliant document"
  - Rewrite `UPSTREAM.md` to point at Venus instead of Moonwell
  - **Verification contract for T46 / Commit B1 (Foundry RED is acceptable)**: `pnpm --filter @endure/contracts hardhat compile` exits 0; `pnpm --filter @endure/contracts hardhat test` exits 0; Stance B audit (with updated path mapping AND test-helpers exclusion) exits 0; `STRICT=1 bash scripts/check-forbidden-patterns.sh` exits 0 (Moonwell deleted in T45 + flag flipped here). **Foundry side (`forge build`, `forge test`) may FAIL on this commit because the old `EndureDeployHelper.sol` (Moonwell) still exists and references types deleted in T45 — that is acceptable; T46b restores Foundry GREEN by deleting the old helper and renaming the Venus one.** This is the deliberate B1/B2 split per Metis recommendation.

  **Must NOT do**:
  - Do NOT manually edit imports — use `sed` or `ast-grep` for safety + auditability
  - Do NOT skip the audit script + CI yaml update (would silently false-green)
  - Do NOT leave the `src/venus-staging/` directory in place
  - Do NOT defer FORK_MANIFEST.md rewrite (it's part of the atomic green-state)

  **Recommended Agent Profile**: `deep` — High-stakes mechanical transformation requiring careful verification
  **Skills**: `[verification-before-completion]`

  **Parallelization**: NO — sequential after T45
  **Blocks**: T47–T51 (docs reflect steady-state)
  **Blocked By**: T45

  **References**:

  **Pattern References**:
  - Spec lines 316–325 (final commit description: `git mv` + import rewrite + audit script update)
  - Existing `packages/contracts/remappings.txt` (`@protocol/=src/`)
  - `packages/contracts/FORK_MANIFEST.md` (Phase 0 Moonwell version) — structure to mirror

  **API/Type References**:
  - `git mv` per-top-level-subdir
  - `sed -i` or `ast-grep` for bulk rewrite

  **External References**:
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:316-326` — final commit description
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:429-443` — FORK_MANIFEST.md regen
  - `docs/briefs/phase-0.5-venus-rebase-spec.md:441` — UPSTREAM.md mandate

  **WHY Each Reference Matters**:
  - The bulk rewrite is the highest-risk single operation in the rebase; using `sed` makes it auditable in `git diff`
  - The audit script update MUST happen in this commit so subsequent CI runs use correct path mapping

  **Acceptance Criteria** (T46 / Commit B1 specifically — T46b/Commit B2 has its own):
  - [ ] `packages/contracts/src/venus-staging/` does NOT exist
  - [ ] `packages/contracts/src/Comptroller/Diamond/Diamond.sol` (and full Venus tree) exists at top level
  - [ ] BOTH `packages/contracts/test/helper/EndureDeployHelper.sol` (Phase 0 Moonwell, no longer compilable since T45) AND `packages/contracts/test/helper/EndureDeployHelperVenus.sol` (Venus, working) STILL EXIST after this commit (teardown is T46b)
  - [ ] `packages/contracts/hardhat.config.ts` `paths.sources` == `"./src"` (no longer `"./src/venus-staging"`)
  - [ ] `pnpm --filter @endure/contracts hardhat compile` exits 0 (Hardhat path flip works)
  - [ ] `pnpm --filter @endure/contracts hardhat test` exits 0 (Hardhat tests pass with new paths)
  - [ ] Stance B audit (with updated path mapping AND test-helpers exclusion) exits 0
  - [ ] **EXPECTED**: `forge build --root packages/contracts` may FAIL on this commit (old Moonwell helper references deleted types) — this is acceptable; T46b restores green
  - [ ] **EXPECTED**: `forge test --root packages/contracts` may FAIL on this commit (build error) — restored by T46b
  - [ ] `FORK_MANIFEST.md` minimally updated (full rewrite deferred to T49) and `UPSTREAM.md` reflects steady-state Venus layout
  - [ ] Forbidden-patterns scan (now hard-gate after this commit removes `continue-on-error`) exits 0 (no Moonwell remnants in `src/`; only the old helper in `test/helper/` references Moonwell types and is about to be deleted in T46b)

  **QA Scenarios**:

  ```
  Scenario: Mass-move complete; Hardhat green; Foundry expected RED (T46b restores)
    Tool: Bash
    Preconditions: T45 committed (CI red), now on Commit B1 WIP
    Steps:
      1. Run: ls packages/contracts/src/venus-staging 2>&1 | tee .sisyphus/evidence/task-46-staging-gone.log
      2. Run: ls packages/contracts/src/Comptroller/Diamond/Diamond.sol | tee .sisyphus/evidence/task-46-venus-promoted.log
      3. Run: ls packages/contracts/test/helper/EndureDeployHelper.sol packages/contracts/test/helper/EndureDeployHelperVenus.sol | tee .sisyphus/evidence/task-46-both-helpers-present.log
      4. Run: forge build --root packages/contracts 2>&1 | tail -10 | tee .sisyphus/evidence/task-46-forge-build.log
      5. Run: pnpm --filter @endure/contracts hardhat compile 2>&1 | tail -10 | tee .sisyphus/evidence/task-46-hardhat-compile.log
      6. Run: pnpm --filter @endure/contracts hardhat test 2>&1 | tail -10 | tee .sisyphus/evidence/task-46-hardhat-test.log
      7. Run: bash scripts/check-stance-b.sh 2>&1 | tee .sisyphus/evidence/task-46-stance-b.log
      8. Assert: staging gone; both helpers present; Hardhat compile + test green; Stance B green; forge build EXPECTED to fail (acceptable)
    Expected Result: Hardhat side green; Stance B clean; Foundry RED is acceptable (T46b will restore)
    Failure Indicators: Staging directory still present; Hardhat broken; Stance B mismatch
    Evidence: .sisyphus/evidence/task-46-{staging-gone,venus-promoted,both-helpers-present,forge-build,hardhat-compile,hardhat-test,stance-b}.log

  Scenario: Three-commit atomicity verified in git log (A + B1 + B2)
    Tool: Bash
    Preconditions: T46 committed (T46b will follow)
    Steps:
      1. Run: git log --oneline -3 | tee .sisyphus/evidence/task-46-loghistory.log
      2. Assert: HEAD is Commit B1 (mass-move); HEAD~1 is Commit A (delete moonwell); HEAD~2 is pre-Chunk-5b
    Expected Result: Three-commit split preserved (A → B1 → B2 still pending)
    Failure Indicators: Single combined commit, missing Commit A
    Evidence: .sisyphus/evidence/task-46-loghistory.log
  ```

  **Evidence to Capture**:
  - [ ] All 8 `.sisyphus/evidence/task-46-*.log` files
  - [ ] `.sisyphus/evidence/task-46-loghistory.log`

  **Commit**: YES (Commit B1 of Chunk 5b)
  - Message: `feat(contracts): mass-move venus-staging to src + import path updates (B1 of 2)`
  - Files: many `git mv` ops + many `@protocol/venus-staging/X` → `@protocol/X` import edits + `FORK_MANIFEST.md` (minimal) + `UPSTREAM.md` + `scripts/check-stance-b.sh` (path mapping + test-helpers exclusion) + `.github/workflows/ci.yml` (remove `continue-on-error` from forbidden-patterns) + `packages/contracts/hardhat.config.ts` (`paths.sources` flip)
  - Pre-commit: Hardhat side green; Foundry side may be RED (acceptable — T46b restores)

- [ ] 46b. **Commit B2 — Dual-helper teardown: delete old Moonwell helper, rename Venus helper, bulk struct rename, restore Foundry GREEN**

  **What to do**:
  - Delete the OLD `packages/contracts/test/helper/EndureDeployHelper.sol` (Phase 0 Moonwell helper — no longer compilable since T45 deleted Moonwell types it referenced)
  - Run: `git mv packages/contracts/test/helper/EndureDeployHelperVenus.sol packages/contracts/test/helper/EndureDeployHelper.sol` so the steady-state name is back to `EndureDeployHelper.sol`
  - Bulk import rewrite (use `sed` or `ast-grep`): `EndureDeployHelperVenus` → `EndureDeployHelper` across ALL of:
    - `packages/contracts/test/endure/**/*.sol`
    - `packages/contracts/test/endure/venus/**/*.sol`
    - `packages/contracts/test/helper/**/*.sol` (BaseTest etc.)
    - `packages/deploy/src/**/*.sol`
    - any `script/`, `proposals/` files that imported the Venus helper
  - Bulk struct rename (use `sed` or `ast-grep`): `VenusAddresses` → `Addresses` across the same file set
  - **Lockfile flip**: Update `.github/workflows/ci.yml` Hardhat-related jobs (`contracts-hardhat-build`, `contracts-hardhat-test`) to use `pnpm install --frozen-lockfile` (remove `=false`). The dependency surface has been stable through Wave 4; flipping to frozen ensures CI catches any unintended `pnpm-lock.yaml` drift in future PRs. Local devs still use the default behavior; only CI enforces frozen.
  - Verify: `forge build --root packages/contracts` exits 0; `forge test --root packages/contracts` exits 0; full CI green end-to-end (with frozen lockfile)
  - This commit is intentionally SMALL and COSMETIC — its diff should be entirely renames + deletions + the lockfile-flag tweak, no logic changes

  **Must NOT do**:
  - Do NOT do this in the same commit as T46 (Metis-recommended split for reviewability)
  - Do NOT use IDE refactoring tools that might introduce silent type changes — use `sed`/`ast-grep` so the diff is auditable
  - Do NOT introduce any logic change in this commit (cosmetic only)

  **Recommended Agent Profile**: `quick` — Mechanical rename + deletion + bulk-edit
  **Skills**: `[]`

  **Parallelization**: NO — sequential after T46
  **Blocks**: T47–T51 (docs reflect steady-state including the canonical helper name)
  **Blocked By**: T46

  **References**:
  - T46 (Commit B1) for the mass-move state this builds on
  - T9 commitment (line 938): "T46 (Chunk 5b Commit B) deletes the old Moonwell helper and renames `EndureDeployHelperVenus.sol` → `EndureDeployHelper.sol`" — this task fulfills that commitment

  **WHY**: Splitting the structural mass-move (T46) from the cosmetic rename (T46b) makes both diffs reviewable independently. Per Metis: "Pure `git mv` + `sed` — mechanically auditable" for B1; "Naming-only changes — small diff, easy review" for B2. If something breaks, granular reversal is possible.

  **Acceptance Criteria**:
  - [ ] OLD `packages/contracts/test/helper/EndureDeployHelper.sol` (Moonwell) does NOT exist (deleted)
  - [ ] `packages/contracts/test/helper/EndureDeployHelper.sol` exists with the Venus implementation (renamed from EndureDeployHelperVenus)
  - [ ] `packages/contracts/test/helper/EndureDeployHelperVenus.sol` does NOT exist (renamed away)
  - [ ] `grep -r "EndureDeployHelperVenus" packages/contracts packages/deploy` returns 0 matches
  - [ ] `grep -r "VenusAddresses" packages/contracts packages/deploy` returns 0 matches (struct rename complete)
  - [ ] `forge build --root packages/contracts` exits 0 (FOUNDRY GREEN RESTORED)
  - [ ] `forge test --root packages/contracts` exits 0 (all tests pass with steady-state names)
  - [ ] `pnpm --filter @endure/contracts hardhat compile` still exits 0
  - [ ] `pnpm --filter @endure/contracts hardhat test` still exits 0
  - [ ] Stance B audit + forbidden-patterns + check-test-mapping all exit 0
  - [ ] CI yaml `contracts-hardhat-build` and `contracts-hardhat-test` jobs now use `pnpm install --frozen-lockfile` (without `=false`)
  - [ ] Diff is renames + deletions + 1 small CI yaml flag tweak ONLY (no logic changes — verifiable by `git diff` reviewer)

  **QA Scenarios**:

  ```
  Scenario: Foundry GREEN restored; all CI checks pass
    Tool: Bash
    Preconditions: T46 (Commit B1) committed; ready for B2
    Steps:
      1. Run: ls packages/contracts/test/helper/EndureDeployHelperVenus.sol 2>&1 | tee .sisyphus/evidence/task-46b-venus-name-gone.log (expected: No such file)
      2. Run: ls packages/contracts/test/helper/EndureDeployHelper.sol | tee .sisyphus/evidence/task-46b-canonical-name.log (expected: present)
      3. Run: head -5 packages/contracts/test/helper/EndureDeployHelper.sol | tee .sisyphus/evidence/task-46b-helper-content.log (expected: Venus implementation, NOT Moonwell)
      4. Run: grep -r "EndureDeployHelperVenus\|VenusAddresses" packages/contracts packages/deploy 2>&1 | tee .sisyphus/evidence/task-46b-no-venus-suffix.log (expected: 0 matches)
      5. Run: forge build --root packages/contracts 2>&1 | tail -5 | tee .sisyphus/evidence/task-46b-forge-build.log
      6. Run: forge test --root packages/contracts 2>&1 | tail -5 | tee .sisyphus/evidence/task-46b-forge-test.log
      7. Run: pnpm --filter @endure/contracts hardhat compile 2>&1 | tail -5 | tee .sisyphus/evidence/task-46b-hh-compile.log
      8. Run: pnpm --filter @endure/contracts hardhat test 2>&1 | tail -5 | tee .sisyphus/evidence/task-46b-hh-test.log
      9. Run: bash scripts/check-stance-b.sh 2>&1 | tee .sisyphus/evidence/task-46b-stance-b.log
      10. Run: bash scripts/check-forbidden-patterns.sh 2>&1 | tee .sisyphus/evidence/task-46b-patterns.log
      11. Run: bash scripts/check-test-mapping.sh 2>&1 | tee .sisyphus/evidence/task-46b-mapping.log
      12. Assert: rename complete; both build commands green; all 5 audit scripts green
    Expected Result: Foundry GREEN restored; full CI green end-to-end
    Failure Indicators: Stale Venus suffix in any file; build error; any audit script failure
    Evidence: 11 `.sisyphus/evidence/task-46b-*.log` files

  Scenario: Three-commit Chunk 5b atomicity preserved
    Tool: Bash
    Preconditions: T46b committed
    Steps:
      1. Run: git log --oneline -4 | tee .sisyphus/evidence/task-46b-loghistory.log
      2. Assert: HEAD is Commit B2 (helper teardown); HEAD~1 is B1 (mass-move); HEAD~2 is A (delete moonwell); HEAD~3 is pre-Chunk-5b
      3. Verify ALL THREE commits are distinct SHAs (no bundling)
    Expected Result: Three atomic commits in correct order
    Failure Indicators: Bundled commits; missing intermediate commit
    Evidence: .sisyphus/evidence/task-46b-loghistory.log

  Scenario: Diff content is rename-only (no hidden logic changes)
    Tool: Bash
    Preconditions: T46b committed
    Steps:
      1. Run: git diff HEAD~1 HEAD --stat | tee .sisyphus/evidence/task-46b-diff-stat.log
      2. Run: git diff HEAD~1 HEAD --diff-filter=R --name-status | tee .sisyphus/evidence/task-46b-renames.log (renames)
      3. Run: git diff HEAD~1 HEAD --diff-filter=D --name-status | tee .sisyphus/evidence/task-46b-deletes.log (deletes — should include the old Moonwell helper)
      4. Run: git diff HEAD~1 HEAD --diff-filter=M --name-only | tee .sisyphus/evidence/task-46b-modifies.log (modifies — should be import-rewrite-only)
      5. Manually inspect a 3-file sample of M diffs: confirm changes are ONLY token replacements (EndureDeployHelperVenus → EndureDeployHelper, VenusAddresses → Addresses). Save sample to .sisyphus/evidence/task-46b-diff-sample.log
    Expected Result: Diff is mechanical (renames + deletes + token-substitution modifies); zero logic changes
    Failure Indicators: Any modify diff that includes non-rename content (e.g., logic changes snuck in)
    Evidence: .sisyphus/evidence/task-46b-{diff-stat,renames,deletes,modifies,diff-sample}.log
  ```

  **Evidence to Capture**:
  - [ ] All 11 `.sisyphus/evidence/task-46b-*.log` files
  - [ ] `.sisyphus/evidence/task-46b-loghistory.log`
  - [ ] `.sisyphus/evidence/task-46b-{diff-stat,renames,deletes,modifies,diff-sample}.log`

  **Commit**: YES (Commit B2 of Chunk 5b)
  - Message: `refactor(contracts): teardown dual-helper — rename to canonical names (B2 of 2)`
  - Files: `packages/contracts/test/helper/EndureDeployHelper.sol` (deleted Moonwell), `packages/contracts/test/helper/EndureDeployHelper.sol` (renamed from Venus), bulk import + struct renames across test/, packages/deploy/, possibly script/
  - Pre-commit: full CI green end-to-end (this is the "GREEN restored" commit)

---

### Wave 7 — Documentation (Chunk 6)

- [ ] 47. **Rewrite `packages/contracts/README.md` for Venus chassis + market params + deployment + test suites**

  **What to do**:
  - Replace `packages/contracts/README.md` content:
    - Header: "Endure Network — Contracts (Venus Core Pool fork)"
    - Section "Architecture": Venus Comptroller + Unitroller + Diamond + 4 facets + ComptrollerLens + ResilientOracle + ACM
    - Section "Markets": vWTAO (borrow asset, CF=0, LT=0), vAlpha30 / vAlpha64 (collateral-only, CF=0.25, LT=0.35)
    - Section "Deployment": `forge script packages/deploy/src/DeployLocal.s.sol --rpc-url <url> --broadcast`
    - Section "Test Suites": Foundry (`forge test`) + Hardhat (`pnpm hardhat test`); description of behavior-mapping table
    - Section "Toolchain": Foundry primary + Hardhat additive; dual solc 0.8.25 + 0.5.16; cancun EVM
    - Section "Stance B": byte-identity audit against Venus pin `6400a067`
    - Remove ALL Moonwell references

  **Must NOT do**: Keep any Moonwell references; mention features explicitly out of scope (no flash loans, no VAI/Prime/XVS as Endure features).

  **Recommended Agent Profile**: `writing` — Technical documentation
  **Parallelization**: YES within Wave 7
  **Blocks**: nothing
  **Blocked By**: T46

  **References**: `packages/contracts/README.md` (Phase 0 version), spec section "Final-state success criteria".

  **WHY**: README is the entry point for new contributors; stale Moonwell references are the most common AI/human confusion source.

  **Acceptance Criteria**:
  - [ ] No "Moonwell" / "MToken" / "mWell" / "WELL" mentions outside historical context section (if any)
  - [ ] Deployment command documented and working
  - [ ] All test commands documented and working

  **QA Scenarios**:

  ```
  Scenario: README accurate and Moonwell-free
    Tool: Bash
    Preconditions: T46 done
    Steps:
      1. Run: grep -i "moonwell\|mtoken\|mwell\|\bWELL\b" packages/contracts/README.md | tee .sisyphus/evidence/task-47-moonwell-grep.log
      2. Assert: 0 hits (or only inside a "Historical Phase 0" footnote section, which is OK)
      3. Verify documented `forge script ...` command actually works (just check syntax matches T12 invocation)
    Expected Result: README clean
    Evidence: .sisyphus/evidence/task-47-moonwell-grep.log
  ```

  **Evidence to Capture**: `.sisyphus/evidence/task-47-moonwell-grep.log`

  **Commit**: YES — `docs(contracts): rewrite README for venus chassis`

- [ ] 48. **Rewrite `packages/contracts/UPSTREAM.md` to declare Venus as upstream + mark stale brief SUPERSEDED**

  **What to do**:
  - Replace `packages/contracts/UPSTREAM.md` content:
    - Pinned upstream: `VenusProtocol/venus-protocol` commit `6400a067114a101bd3bebfca2a4bd06480e84831` (tag `v10.2.0-dev.5`)
    - Synchronization policy: pin is locked; future Venus updates are explicit decisions
    - Stance B audit reference
    - Pinned commits for each `lib/venusprotocol-*` package
  - Was already partially updated in T40 / T46; this is the final pass
  - **ALSO**: Add a SUPERSEDED banner to the top of `docs/briefs/phase-0.5-venus-rebase-brief.md` (currently pins `7c95843d` / `v10.2.0-dev.4`, both stale). The banner content:
    ```
    > **⚠ SUPERSEDED**: This brief is retained as historical Stage A evidence and is **NOT authoritative** for execution. The authoritative spec is `docs/briefs/phase-0.5-venus-rebase-spec.md` (pinned at `6400a067` / `v10.2.0-dev.5`). The implementation plan is `.sisyphus/plans/phase-0.5-venus-rebase.md`.
    ```
  - Place the banner immediately after the title line, before any other content.

  **Must NOT do**:
  - Keep Moonwell as the upstream.
  - Delete the brief — it stays for historical reference, just clearly marked.

  **Recommended Agent Profile**: `writing`
  **Parallelization**: YES within Wave 7
  **Blocks**: nothing
  **Blocked By**: T46

  **References**: `packages/contracts/UPSTREAM.md` (Phase 0), spec line 441.

  **Acceptance Criteria**:
  - [ ] `packages/contracts/UPSTREAM.md` references Venus pin `6400a067`
  - [ ] `packages/contracts/UPSTREAM.md` has no Moonwell references (live)
  - [ ] `docs/briefs/phase-0.5-venus-rebase-brief.md` has the SUPERSEDED banner at the top (pointing at the spec + plan)
  - [ ] The brief itself is NOT deleted (retained for historical reference)

  **QA Scenarios**:

  ```
  Scenario: UPSTREAM.md Venus-pinned + brief marked SUPERSEDED
    Tool: Bash
    Steps:
      1. Run: grep "6400a067" packages/contracts/UPSTREAM.md | tee .sisyphus/evidence/task-48-pin.log
      2. Run: grep -i "moonwell" packages/contracts/UPSTREAM.md | tee .sisyphus/evidence/task-48-moonwell.log
      3. Run: head -5 docs/briefs/phase-0.5-venus-rebase-brief.md | grep -iE "SUPERSEDED|not authoritative" | tee .sisyphus/evidence/task-48-brief-banner.log
      4. Assert: pin present in UPSTREAM.md; no Moonwell mention in UPSTREAM.md; SUPERSEDED banner present at top of brief
    Evidence: .sisyphus/evidence/task-48-{pin,moonwell,brief-banner}.log
  ```

  **Commit**: YES — `docs(contracts): rewrite UPSTREAM for venus pin + mark stale brief superseded`

- [ ] 49. **Rewrite `packages/contracts/FORK_MANIFEST.md` to FULL steady-state Venus layout (T46 did the minimum; this is the comprehensive version)**

  **What to do**:
  - **OWNERSHIP CLARIFICATION**: T46 did the MINIMUM required for Stance B to pass post-move (path-mapping fixes + Section 6.7 preserved). T49 OWNS the full spec-compliant 6-section rewrite. There is no overlap — T46 unblocks CI; T49 produces the canonical document.
  - Comprehensive rewrite to spec-compliant 6-section format (per spec lines 429–443):
    - Section "Pinned upstream" — `VenusProtocol/venus-protocol` commit `6400a067114a101bd3bebfca2a4bd06480e84831` (tag `v10.2.0-dev.5`)
    - Section "Files vendored byte-identical" — full auto-generated path list under `src/` (excluding `src/endure/` and `src/test-helpers/venus/`). Generate via: `find packages/contracts/src -name "*.sol" -not -path "*/endure/*" -not -path "*/test-helpers/*" | sort`
    - Section "Files vendored byte-identical from Venus test/" — full path list under `src/test-helpers/venus/`. Generate via: `find packages/contracts/src/test-helpers/venus -name "*.sol" | sort`
    - Section "Endure-authored files" — full path list under `src/endure/`. Generate via: `find packages/contracts/src/endure -name "*.sol" | sort`
    - Section "Documented deviations" — enumerated entries with rationale (expected: empty if Stance B is clean; if not empty, every entry must have a Stance B exception note)
    - Section "Files explicitly NOT vendored" — empty per Decision #2 (full-tree vendor)
    - Section "Pinned dependency commits" — REPLACE the npm-version table with the SHA table from Section 6.7 (T25c). Each `lib/venusprotocol-*` row has package name + npm version + upstream repo + git commit SHA.
    - Section "Phase 0 Historical Audit Trail" (carried forward from T45's archived Sections 1–5) — preserved at the end of the file as historical reference
  - Verify ALL lists auto-generated correctly; no Phase 0 Moonwell live references; clean Stance B audit re-run after rewrite

  **Must NOT do**: Keep any Moonwell entries.

  **Recommended Agent Profile**: `writing` — Manifest accuracy critical
  **Parallelization**: YES within Wave 7
  **Blocks**: nothing
  **Blocked By**: T46

  **References**: spec lines 429–443

  **Acceptance Criteria**:
  - [ ] All 6 sections present and accurate
  - [ ] Stance B audit re-run after manifest update still passes

  **QA Scenarios**:

  ```
  Scenario: FORK_MANIFEST sections complete and accurate
    Tool: Bash
    Steps:
      1. Run: grep -E "^## " packages/contracts/FORK_MANIFEST.md | tee .sisyphus/evidence/task-49-sections.log
      2. Run: bash scripts/check-stance-b.sh 2>&1 | tee .sisyphus/evidence/task-49-audit.log
      3. Assert: 6 expected section headers present; audit clean
    Evidence: .sisyphus/evidence/task-49-{sections,audit}.log
  ```

  **Commit**: YES — `docs(contracts): finalize FORK_MANIFEST for steady-state venus layout`

- [ ] 50. **Rewrite `skills/endure-architecture/SKILL.md` to reflect Venus-based architecture**

  **What to do**:
  - Update `skills/endure-architecture/SKILL.md`:
    - Lending chassis: Venus Core Pool (was: Moonwell v2)
    - CF/LT separation: explicit description
    - Diamond pattern + 4 facets: enumeration
    - Mock surface: `MockResilientOracle`, `AllowAllAccessControlManager`
    - Out-of-scope features: VAI/Prime/XVS as Endure features (vendored only); flash loans not exposed; external Liquidator absent
    - Test infrastructure: dual Foundry + Hardhat
    - Stance B byte-identity at Venus pin `6400a067`

  **Must NOT do**: Reference Moonwell as the live chassis.

  **Recommended Agent Profile**: `writing`
  **Parallelization**: YES within Wave 7
  **Blocks**: nothing
  **Blocked By**: T46

  **References**: existing `skills/endure-architecture/SKILL.md`; spec section "Locked Endure architecture remains unchanged except the chassis" (lines 105–112).

  **Acceptance Criteria**:
  - [ ] No Moonwell references as live chassis (historical mention OK)
  - [ ] Venus chassis fully described
  - [ ] All locked architectural decisions reflected

  **QA Scenarios**:

  ```
  Scenario: SKILL.md reflects Venus architecture
    Tool: Bash
    Steps:
      1. Run: grep -i "venus\|diamond\|facet\|resilient" skills/endure-architecture/SKILL.md | wc -l | tee .sisyphus/evidence/task-50-venus-mentions.log
      2. Run: grep -i "moonwell" skills/endure-architecture/SKILL.md | tee .sisyphus/evidence/task-50-moonwell.log
      3. Assert: ≥10 Venus mentions; only historical Moonwell mentions
    Evidence: .sisyphus/evidence/task-50-{venus-mentions,moonwell}.log
  ```

  **Commit**: YES — `docs(skill): update endure-architecture for venus`

- [ ] 51. **Update root `README.md` references to Venus + add Venus-specific footguns appendix**

  **What to do**:
  - Update root `/README.md`:
    - Header description: "Endure is a lending protocol built as a Venus Protocol Core Pool fork" (was: "Moonwell v2 fork")
    - Update `packages/contracts/README.md` link description
  - Add a new top-level section "Venus-Specific Footguns" (or append to existing developer-notes section):
    - **CF/LT ordering**: oracle prices MUST be set before nonzero CF/LT
    - **Cap semantics**: `borrowCap == 0` DISABLES borrowing (NOT unlimited)
    - **Diamond selectors**: 71 selectors required (spike's 61 baseline + 10 expansion for RewardFacet usability); missing any silently breaks runtime
    - **ComptrollerLens criticality**: must be deployed and registered via `_setComptrollerLens` BEFORE markets are listed
    - **RewardFacet inclusion**: deployed with all reward speeds zero (PolicyFacet inheritance dependency)
    - **Compound soft-fail returns**: many state-mutation functions return uint error codes instead of reverting; tests must assert return value
    - **`liquidateCalculateSeizeTokens` 4-arg variant**: VToken uses 4-arg; both 3-arg and 4-arg must be registered

  **Must NOT do**: Keep "Moonwell v2 fork" as the description.

  **Recommended Agent Profile**: `writing`
  **Parallelization**: YES within Wave 7
  **Blocks**: F1–F4 (all docs must be done before review)
  **Blocked By**: T46

  **References**: existing root `README.md`; spec line 604 (footguns documentation mandate).

  **Acceptance Criteria**:
  - [ ] Root README header mentions Venus, not Moonwell
  - [ ] Footguns appendix exists and covers all 7 items above

  **QA Scenarios**:

  ```
  Scenario: Root README + footguns updated
    Tool: Bash
    Steps:
      1. Run: head -5 README.md | tee .sisyphus/evidence/task-51-header.log
      2. Run: grep -E "Footgun|footgun|CF/LT|Compound soft-fail|Diamond selector" README.md | tee .sisyphus/evidence/task-51-footguns.log
      3. Assert: header says Venus; ≥5 footgun-related grep matches
    Evidence: .sisyphus/evidence/task-51-{header,footguns}.log
  ```

  **Commit**: YES — `docs: update root README + venus footguns`

---

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before squash-merging to main.
>
> **Do NOT auto-proceed after verification. Wait for user's explicit approval.**
> **Never mark F1–F4 as checked before getting user's okay.** Rejection or user feedback → fix → re-run → present again → wait for okay.

- [ ] F1. **Plan Compliance Audit** — `oracle`

  **What to do**:
  - Read this plan end-to-end (skeleton + all 55 task bodies (T1–T51 + T22b + T25b + T25c + T46b) + Final Verification Wave + Commit Strategy + Success Criteria)
  - For each "Must Have" in Work Objectives: verify implementation exists (read file, run test, run script — concrete verification, not assumption)
  - For each "Must NOT Have" guardrail: search codebase for forbidden patterns; reject with `file:line` if found
  - Verify all 21 final-state success criteria from the spec hold (use the verification commands in Success Criteria section)
  - Check evidence files exist for every task in `.sisyphus/evidence/` (expect ≥51 task evidence sets + final-qa/ subdir)
  - Compare deliverables list (Concrete Deliverables in Work Objectives) vs reality (what's actually in the repo at HEAD)

  **Recommended Agent Profile**:
  - **Category**: `oracle` (read-only consultation; high-IQ reasoning for compliance audit)
  - **Skills**: `[]`

  **Acceptance Criteria**:
  - [ ] Final report enumerates each Must Have with PASS/FAIL + evidence path
  - [ ] Final report enumerates each Must NOT with CLEAN/VIOLATION + `file:line` if violated
  - [ ] All 21 spec criteria addressed
  - [ ] Verdict line: `Must Have [N/N] | Must NOT Have [N/N] | Spec criteria [N/21] | Tasks [N/55] | Evidence files [N] | VERDICT: APPROVE/REJECT` (55 = T1–T51 + T22b + T25b + T25c + T46b)

  **QA Scenarios**:

  ```
  Scenario: Plan compliance verified end-to-end
    Tool: OMO Task tool (preferred) OR Bash (fallback)
    Preconditions: All T1-T51 + T22b + T25b + T25c + T46b implementation tasks complete; evidence files written
    Steps:
      1. PREFERRED — Invoke the OMO Task tool with subagent_type="oracle" (or via /start-work's dispatcher; whatever mechanism the runtime exposes for spawning a sub-agent). Prompt: "Read .sisyphus/plans/phase-0.5-venus-rebase.md end-to-end. Audit Must Have / Must NOT lists against repo HEAD using only Read/Grep/Bash. Verify all 21 spec criteria. Verify all 55 tasks have evidence files in .sisyphus/evidence/. Output structured report to .sisyphus/evidence/final-F1-compliance.md ending with: `Must Have [N/N] | Must NOT Have [N/N] | Spec criteria [N/21] | Tasks [N/55] | Evidence files [N] | VERDICT: APPROVE/REJECT`."
      2. FALLBACK if no Task-tool dispatcher available — Manually run a sub-agent equivalent: a human reviewer or a fresh `claude` CLI session with the same prompt, writing output to the same path.
      3. Wait for completion (background notification if async; synchronous return otherwise)
      4. `cat .sisyphus/evidence/final-F1-compliance.md` — read and inspect
      5. `tail -1 .sisyphus/evidence/final-F1-compliance.md | grep -E "VERDICT: APPROVE"` — assert the report ends with APPROVE
      6. `grep -cE "^.*FAIL|^.*VIOLATION" .sisyphus/evidence/final-F1-compliance.md` — assert returns 0
      7. `grep -c "PASS" .sisyphus/evidence/final-F1-compliance.md` — assert ≥ 21
    Expected Result: Compliance report APPROVE; zero FAIL/VIOLATION lines; ≥21 PASS lines
    Failure Indicators: Any FAIL/VIOLATION line, missing spec criteria, REJECT verdict, oracle reports unverifiable items, dispatcher unavailable AND no fallback executed
    Evidence: .sisyphus/evidence/final-F1-compliance.md
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/final-F1-compliance.md`

- [ ] F2. **Code Quality + Build Review** — `unspecified-high`

  **What to do**:
  - Run full build matrix: `forge build --root packages/contracts`, `forge test --root packages/contracts`, `pnpm --filter @endure/contracts hardhat compile`, `pnpm --filter @endure/contracts hardhat test`
  - Run all CI scripts locally: `scripts/check-forbidden-patterns.sh`, `scripts/check-stance-b.sh`, `scripts/check-test-mapping.sh`, `scripts/check-hardhat-skips.sh`, `scripts/gas-snapshot-check.sh`
  - Review all files changed during Chunks 1-6 (use `git diff main..HEAD --name-only` to enumerate) for: `as any` / `@ts-ignore` (TypeScript), unused imports, commented-out code blocks, `console.log` in production paths, AI slop patterns (excessive comments explaining the obvious, over-abstraction, generic names like `data`/`result`/`item`/`temp`/`util`), TODO/FIXME comments left behind
  - Spot-check 5 randomly selected vendored Venus files to confirm they were NOT modified (Stance B violation check)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` (multi-tool review; rigorous but not novel reasoning)
  - **Skills**: `[ai-slop-remover]` — for AI slop pattern detection on Endure-authored files

  **Acceptance Criteria**:
  - [ ] All 4 build commands exit 0
  - [ ] All 5 audit scripts exit 0
  - [ ] Per-file review report saved with each Endure-authored file marked CLEAN or with concrete issue list
  - [ ] Verdict line: `forge build [PASS/FAIL] | forge test [N pass/N fail] | hardhat compile [PASS/FAIL] | hardhat test [N pass/N fail] | forbidden-patterns [PASS/FAIL] | stance-b-audit [PASS/FAIL] | check-test-mapping [PASS/FAIL] | check-hardhat-skips [PASS/FAIL] | gas-snapshot-check [PASS/FAIL] | Files reviewed [N clean/N issues] | VERDICT`

  **QA Scenarios**:

  ```
  Scenario: Full build matrix + audit scripts all green
    Tool: Bash
    Preconditions: All T1-T51 implementation complete; on phase-0.5-venus-rebase HEAD
    Steps:
      1. Run: forge build --root packages/contracts 2>&1 | tee .sisyphus/evidence/final-F2-forge-build.log
      2. Run: forge test --root packages/contracts 2>&1 | tee .sisyphus/evidence/final-F2-forge-test.log
      3. Run: pnpm --filter @endure/contracts hardhat compile 2>&1 | tee .sisyphus/evidence/final-F2-hh-compile.log
      4. Run: pnpm --filter @endure/contracts hardhat test 2>&1 | tee .sisyphus/evidence/final-F2-hh-test.log
      5. Run: bash scripts/check-forbidden-patterns.sh 2>&1 | tee .sisyphus/evidence/final-F2-forbidden.log
      6. Run: bash scripts/check-stance-b.sh 2>&1 | tee .sisyphus/evidence/final-F2-stance-b.log
      7. Run: bash scripts/check-test-mapping.sh 2>&1 | tee .sisyphus/evidence/final-F2-mapping.log
      8. Run: bash scripts/check-hardhat-skips.sh 2>&1 | tee .sisyphus/evidence/final-F2-skips.log
      9. Run: bash scripts/gas-snapshot-check.sh 2>&1 | tee .sisyphus/evidence/final-F2-gas.log
      10. Assert: every command exits 0
    Expected Result: All 9 commands green
    Failure Indicators: Any non-zero exit; any test regression; any audit mismatch
    Evidence: .sisyphus/evidence/final-F2-{forge-build,forge-test,hh-compile,hh-test,forbidden,stance-b,mapping,skips,gas}.log

  Scenario: AI slop + code quality review of changed files
    Tool: OMO Task tool (preferred) OR Bash (fallback to scripted slop scan)
    Preconditions: F2 first scenario passed
    Steps:
      1. Run: `git diff main..HEAD --name-only > /tmp/changed-files.txt`
      2. PREFERRED — Invoke the OMO Task tool with subagent_type="unspecified-high", load_skills=["ai-slop-remover"]. Prompt: "Review files in /tmp/changed-files.txt for AI slop, unused imports, console.log in production paths, generic names (data/result/item/temp/util), `as any` / `@ts-ignore`, dead code. For each Endure-authored file (under packages/contracts/src/endure/, packages/contracts/test/endure/, packages/deploy/), output CLEAN or list concrete issues with file:line. Save report to .sisyphus/evidence/final-F2-quality-review.md."
      3. FALLBACK if no Task-tool dispatcher — run a Bash scripted slop scan instead: `for f in $(cat /tmp/changed-files.txt | grep -E '\.(sol|ts|js)$'); do grep -nE "as any|@ts-ignore|console\.log|TODO|FIXME|//\s*temp|//\s*HACK" "$f" | head -3; done > .sisyphus/evidence/final-F2-quality-review.md`. The bash version is a coarser substitute but provides the same evidence trail.
      4. Read report; `grep -cE "CRITICAL|HIGH|as any|@ts-ignore" .sisyphus/evidence/final-F2-quality-review.md` — assert returns 0
    Expected Result: Quality report shows all reviewed files CLEAN or only LOW-severity findings
    Failure Indicators: Any CRITICAL/HIGH issue, e.g. `as any` in committed TS, dead code, slop patterns
    Evidence: .sisyphus/evidence/final-F2-quality-review.md
  ```

  **Evidence to Capture**:
  - [ ] All 9 `.sisyphus/evidence/final-F2-*.log` files
  - [ ] `.sisyphus/evidence/final-F2-quality-review.md`

- [ ] F3. **Real Manual QA** — `unspecified-high`

  **What to do**:
  - Start from clean state: kill any existing anvil, clear `packages/deploy/addresses.json` if present
  - Spin up fresh Anvil; deploy via `forge script`; capture `addresses.json`
  - Execute `scripts/e2e-smoke.sh` against the live deployment
  - Execute every QA scenario from every task T1–T51 sequentially in a clean integration run (use the QA Scenarios already in each task body)
  - Specific cross-task integration tests:
    - Mint mock alpha → approve vAlpha30 → enterMarkets → supply → borrow vWTAO → drop oracle price → direct vToken liquidation (no external Liquidator) → assert seized collateral transferred to liquidator
    - Attempt borrow on vAlpha30 (cap=0) → assert non-zero return code
    - Deploy fresh chassis without setting oracle, attempt `setCollateralFactor(vAlpha, 0.25e18, 0.35e18)` (no leading underscore — Venus naming) → assert non-zero return code
    - Attempt `setCollateralFactor(vAlpha, 0.4e18, 0.3e18)` (LT<CF) → assert non-zero return code
  - Edge cases: empty state, rapid sequential txns, simultaneous borrows from multiple users (use `vm.prank` rotation if needed)
  - Save all evidence to `.sisyphus/evidence/final-qa/` (subdirectory)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high` (heavy execution; mostly Bash + cast)
  - **Skills**: `[]` — no Playwright needed (no browser UI in this work)

  **Acceptance Criteria**:
  - [ ] Anvil deploy succeeds (exit 0)
  - [ ] `e2e-smoke.sh` exits 0
  - [ ] Direct liquidation succeeds (no external Liquidator path used)
  - [ ] All 4 specific cross-task integration tests pass
  - [ ] Edge cases tested with documented results
  - [ ] All evidence in `.sisyphus/evidence/final-qa/`
  - [ ] Verdict line: `Anvil deploy [PASS/FAIL] | e2e-smoke [PASS/FAIL] | Direct liquidation [PASS/FAIL] | borrowCap=0 rejection [PASS/FAIL] | oracle-unset rejection [PASS/FAIL] | LT<CF rejection [PASS/FAIL] | Edge cases [N tested] | VERDICT`

  **QA Scenarios**:

  ```
  Scenario: Anvil deploy + e2e-smoke from clean state
    Tool: Bash
    Preconditions: T46 complete (mass-move done); clean working tree
    Steps:
      1. Run: pkill -f anvil || true
      2. Run: rm -f packages/deploy/addresses.json
      3. Run: anvil --port 8545 > /tmp/final-anvil.log 2>&1 &
      4. Sleep 2
      5. Run: forge script packages/deploy/src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 2>&1 | tee .sisyphus/evidence/final-qa/F3-deploy.log
      6. Run: bash scripts/e2e-smoke.sh 2>&1 | tee .sisyphus/evidence/final-qa/F3-smoke.log
      7. Assert: deploy exits 0; smoke exits 0
    Expected Result: Both succeed
    Failure Indicators: Any non-zero exit, missing addresses.json, smoke revert
    Evidence: .sisyphus/evidence/final-qa/F3-{deploy,smoke}.log

  Scenario: Direct vToken liquidation (no external Liquidator)
    Tool: Bash + cast
    Preconditions: Previous scenario passed; Anvil still live
    Steps:
      1. Read addresses from packages/deploy/addresses.json into env vars (jq)
      2. Use cast send to: as Alice, mint alpha → approve vAlpha30 → enterMarkets → mint vAlpha30 (supply) → borrow vWTAO
      3. Use cast send to: as deployer, set oracle price for alpha to 0.5x original via MockResilientOracle.setUnderlyingPrice
      4. Use cast send to: as Bob, call vWTAO.liquidateBorrow(alice, repayAmount, vAlpha30) — capture tx receipt
      5. Use cast call to: read Bob's balance of vAlpha30 — assert > 0 (seized collateral received)
      6. Verify NO external Liquidator address was used (grep tx logs for liquidatorContract address — should be address(0) or unused)
    Expected Result: Liquidation succeeds; Bob receives seized vAlpha30
    Failure Indicators: Liquidation reverts, Bob balance unchanged, external Liquidator path triggered
    Evidence: .sisyphus/evidence/final-qa/F3-direct-liquidation.log

  Scenario: borrowCap=0 disables borrow
    Tool: Bash + cast
    Steps:
      1. Use cast call to confirm Comptroller(unitroller).borrowCaps(vAlpha30) == 0
      2. Use cast send: as Alice (with alpha collateral entered), call vAlpha30.borrow(1)
      3. Capture return code from tx (use cast --json + jq on logs to extract Compound Failure event code)
      4. Assert: return code != 0 OR tx reverted with "borrow not allowed"
    Expected Result: Borrow rejected
    Failure Indicators: Borrow succeeds (Moonwell semantic regression)
    Evidence: .sisyphus/evidence/final-qa/F3-cap-zero.log

  Scenario: Oracle-unset CF rejection + LT<CF rejection
    Tool: Bash (forge test driver running ad-hoc Solidity test)
    Steps:
      1. Author a one-off test file .sisyphus/scratch/F3OracleAndLTCF.t.sol that:
         - Deploys chassis WITHOUT calling MockResilientOracle.setUnderlyingPrice
         - Attempts setCollateralFactor(vAlpha, 0.25e18, 0.35e18) (no leading underscore — Venus naming); assert return != 0
         - In a separate test, sets oracle, attempts setCollateralFactor(vAlpha, 0.4e18, 0.3e18); assert return != 0
      2. Run: forge test --match-path .sisyphus/scratch/F3OracleAndLTCF.t.sol -vvv 2>&1 | tee .sisyphus/evidence/final-qa/F3-cf-ordering.log
      3. Assert: both tests pass
    Expected Result: Both rejection paths verified
    Failure Indicators: Either CF call returns 0 (success when it should reject)
    Evidence: .sisyphus/evidence/final-qa/F3-cf-ordering.log

  Scenario: All per-task QA scenarios re-run in integration
    Tool: Bash
    Steps:
      1. For each T1-T51 with QA scenarios: re-run them sequentially (or rerun forge test --root packages/contracts which exercises the foundry-side scenarios)
      2. Run: pnpm --filter @endure/contracts hardhat test 2>&1 | tee .sisyphus/evidence/final-qa/F3-all-hh.log
      3. Assert: all tests pass; full evidence trail intact
    Expected Result: All ports + integration scenarios pass
    Evidence: .sisyphus/evidence/final-qa/F3-all-hh.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/final-qa/F3-deploy.log`
  - [ ] `.sisyphus/evidence/final-qa/F3-smoke.log`
  - [ ] `.sisyphus/evidence/final-qa/F3-direct-liquidation.log`
  - [ ] `.sisyphus/evidence/final-qa/F3-cap-zero.log`
  - [ ] `.sisyphus/evidence/final-qa/F3-cf-ordering.log`
  - [ ] `.sisyphus/evidence/final-qa/F3-all-hh.log`

- [ ] F4. **Scope Fidelity Check** — `deep`

  **What to do**:
  - **File-scope source of truth**: F4 uses the **Commit Strategy** section of this plan (see "Commit Strategy" further below) as the canonical per-task file-scope declaration. Each commit-strategy bullet enumerates the files for one task or task-group. Task bodies do NOT have a separate "Files" section — file scope lives in Commit Strategy.
  - For each task T1–T51 PLUS T22b, T25b, T25c, T46b (55 implementation tasks total):
    - Read task body's "What to do" section in the plan
    - Look up that task's commit-strategy line (bullet starting with `- **TN**:` or `- **TN, TM**:`) to obtain its declared file scope
    - Read actual diff for those files: `git log --all --diff-filter=AMD --name-only --pretty=format: | grep <task-file>` then `git diff <commit>~1 <commit> -- <file>`
    - Verify 1:1: everything in spec was built (no missing line items), nothing beyond spec was built (no creep)
  - Check "Must NOT do" compliance per task: spot-check 10 random tasks for guardrail violations against the task-body "Must NOT do" lists
  - Detect cross-task contamination: for each commit, ensure files changed match the Commit Strategy declared scope for that commit's task(s) — no Task N commit touching Task M's files
  - Flag unaccounted changes: any file changed between branch base and HEAD that doesn't trace to a Commit Strategy entry
  - Verify three-commit split for Chunk 5b held (per Metis recommendation): `git log --oneline | grep -iE "(delete moonwell|mass-move venus|teardown dual-helper)" | wc -l` should return 3 distinct commits (T45 + T46 + T46b)

  **Recommended Agent Profile**:
  - **Category**: `deep` (autonomous reasoning over a large diff; goal-oriented)
  - **Skills**: `[]`

  **Acceptance Criteria**:
  - [ ] Per-task compliance report (51 entries) saved
  - [ ] Contamination report saved (or "CLEAN")
  - [ ] Unaccounted-files list saved (or "CLEAN")
  - [ ] Chunk 5b atomicity verdict
  - [ ] Verdict line: `Tasks [N/55 compliant] | Contamination [CLEAN/N issues] | Unaccounted [CLEAN/N files] | Chunk 5b atomicity [HELD/VIOLATED] | VERDICT` (55 = T1–T51 + T22b + T25b + T25c + T46b)

  **QA Scenarios**:

  ```
  Scenario: Per-task scope fidelity audit
    Tool: OMO Task tool (preferred) OR Bash (fallback to scripted scope check)
    Preconditions: All 55 implementation tasks committed on phase-0.5-venus-rebase
    Steps:
      1. Run: `git log main..HEAD --oneline > /tmp/all-commits.txt`
      2. PREFERRED — Invoke the OMO Task tool with subagent_type="deep". Prompt: "For each of the 55 implementation tasks in .sisyphus/plans/phase-0.5-venus-rebase.md (T1–T51 + T22b + T25b + T25c + T46b), read the task body's 'What to do' section AND the corresponding bullet in the 'Commit Strategy' section (the bullet starting with '- **TN**:' or '- **TN, TM**:' that declares the AUTHORITATIVE file scope per the Exhaustiveness Contract). Then for each task's commit, run git diff and verify 1:1 fidelity between (What to do + declared file scope) and (actual diff). Output report to .sisyphus/evidence/final-F4-fidelity.md with one line per task: `[TASK-N] COMPLIANT|MISSING|CREEP + details`. Final line: `Tasks [N/55 compliant] | Contamination [CLEAN/N issues] | Unaccounted [CLEAN/N files] | Chunk 5b atomicity [HELD/VIOLATED] | VERDICT`."
      3. FALLBACK if no Task-tool dispatcher — run a Bash scripted scope check: extract Commit Strategy bullets via `awk '/^## Commit Strategy/,/^## /' .sisyphus/plans/phase-0.5-venus-rebase.md > /tmp/commit-strategy.txt`; then for each commit in `git log main..HEAD --pretty=format:"%H %s"`, parse the task ID from the subject and verify `git show --name-only $sha` files are a subset of the corresponding bullet's declared scope. Save report to same path.
      4. Read report; count COMPLIANT vs MISSING vs CREEP
      5. `tail -1 .sisyphus/evidence/final-F4-fidelity.md | grep "VERDICT"` and assert ALL of: `[55/55 compliant]`, `Contamination [CLEAN]`, `Unaccounted [CLEAN]`, `Chunk 5b atomicity [HELD]`
    Expected Result: All 55 tasks COMPLIANT; zero contamination; zero unaccounted; Chunk 5b atomicity HELD
    Failure Indicators: Any MISSING (spec item not built) or CREEP (extra unjustified changes); dispatcher unavailable AND no fallback executed
    Evidence: .sisyphus/evidence/final-F4-fidelity.md

  Scenario: Cross-task contamination check
    Tool: Bash
    Preconditions: All commits landed
    Steps:
      1. Run: for commit in $(git log main..HEAD --pretty=format:%H); do git show --stat $commit; done > /tmp/all-diffs.txt
      2. For each commit, parse the commit subject (e.g., `test(endure): port AliceLifecycle to venus`) and look up the matching Commit Strategy bullet to obtain declared file scope
      3. Cross-reference declared scope vs actual changed files in that commit
      4. Save report: .sisyphus/evidence/final-F4-contamination.log
      5. Assert: report says "CLEAN" or 0 contamination issues
    Expected Result: Report says CLEAN; every commit's file changes fall within its task's Commit Strategy declared scope
    Failure Indicators: Task N commit touches files outside its declared scope; commit subject does not map to any Commit Strategy bullet
    Evidence: .sisyphus/evidence/final-F4-contamination.log

  Scenario: Chunk 5b three-commit atomicity verified (A + B1 + B2 per Metis split)
    Tool: Bash
    Steps:
      1. Run: git log main..HEAD --oneline | grep -iE "(delete moonwell|mass-move venus|venus-staging to src|teardown dual-helper|B[12] of 2)" | tee .sisyphus/evidence/final-F4-5b-commits.log
      2. Assert: exactly 3 distinct commits, in order (in reverse-chronological output: B2 first, then B1, then A)
      3. Verify all three commits are distinct SHAs (not bundled)
    Expected Result: Three atomic commits preserved (A → B1 → B2)
    Failure Indicators: Bundled commits; missing intermediate commit; only A + single B (split was reverted)
    Evidence: .sisyphus/evidence/final-F4-5b-commits.log

  Scenario: Unaccounted file changes
    Tool: Bash
    Preconditions: All commits landed
    Steps:
      1. Run: git diff main..HEAD --name-only > /tmp/all-changed-files.txt
      2. Build the union of file paths declared across the entire Commit Strategy section (parse each `- **TN**: ... — <files>` bullet)
      3. For each file in /tmp/all-changed-files.txt, check if it appears in the Commit Strategy union; collect orphans
      4. Save unaccounted list (if any) to .sisyphus/evidence/final-F4-unaccounted.log
      5. Assert: report says "CLEAN" (zero unaccounted) OR every orphan has a documented justification appended
    Expected Result: Report says CLEAN; every file change traces to a Commit Strategy entry
    Failure Indicators: File changed but no Commit Strategy bullet claims responsibility (likely scope creep)
    Evidence: .sisyphus/evidence/final-F4-unaccounted.log
  ```

  **Evidence to Capture**:
  - [ ] `.sisyphus/evidence/final-F4-fidelity.md`
  - [ ] `.sisyphus/evidence/final-F4-contamination.log`
  - [ ] `.sisyphus/evidence/final-F4-5b-commits.log`
  - [ ] `.sisyphus/evidence/final-F4-unaccounted.log`

---

## Commit Strategy

> One PR per chunk into `phase-0.5-venus-rebase`. Within a chunk, commits group by task or related task pair. Final integration: squash-merge `phase-0.5-venus-rebase` → `main` after all chunks green.
>
> **EXHAUSTIVENESS CONTRACT (for F4 Scope Fidelity audit)**: The Files entry in each Commit Strategy bullet below is the AUTHORITATIVE file scope for that commit. F4 derives task-to-commit mapping from these entries. If a task body's "What to do" mentions a file that isn't listed in its Commit Strategy bullet, the bullet must be updated to include it. Implementers MUST NOT commit changes to files not enumerated in the corresponding Commit Strategy bullet without first updating this section.

- **T1**: NO COMMIT (verification-only; no file changes)
- **T2**: `chore(contracts): add hardhat config + ts dependencies` — `packages/contracts/hardhat.config.ts`, `packages/contracts/tsconfig.json`, `packages/contracts/package.json`, `packages/contracts/.gitignore`, `pnpm-lock.yaml`
- **T3–T5**: `chore(contracts): vendor venus hardhat tests + deploy + move test helpers to steady-state path` — `tests/hardhat/`, `deploy/`, `src/test-helpers/venus/` (T5 is a `git mv` from `src/venus-staging/test/` → `src/test-helpers/venus/`, NOT a fresh copy). Stage T3 + T4 changes first, then T5's `git mv`, then commit all three together.
- **T6**: `ci(contracts): add hardhat compile gate` — `.github/workflows/ci.yml`
- **T7, T8**: `test(endure): add deploy + diamond selector failing tests` — `test/endure/venus/Deploy.t.sol`, `DiamondSelectorRouting.t.sol`
- **T9, T10, T11**: `feat(endure): author venus deploy helper (dual-helper strategy) + update IRM params` — `packages/contracts/test/helper/EndureDeployHelperVenus.sol` (NEW file; old Moonwell `EndureDeployHelper.sol` untouched until T46b), `packages/contracts/src/endure/EnduRateModelParams.sol` (T10 updates pragma to 0.8.25 + adds 4-5 Venus TwoKinks constants per market + `BLOCKS_PER_YEAR`)
- **T12**: `feat(deploy): rewrite DeployLocal for venus` — `packages/deploy/src/DeployLocal.s.sol` (imports `EndureDeployHelperVenus`)
- **T13**: `chore(test): add behavior-mapping table + ci enforcement` — `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`, `scripts/check-test-mapping.sh`, `.github/workflows/ci.yml`
- **T14**: `test(endure): port AliceLifecycle to venus` — `packages/contracts/test/endure/integration/AliceLifecycle.t.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T15**: `test(endure): port Liquidation to venus + LT/CF separation` — `packages/contracts/test/endure/integration/Liquidation.t.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T16**: `test(endure): port SeedDeposit to vtokens` — `packages/contracts/test/endure/SeedDeposit.t.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T17**: `test(endure): port RBACSeparation to venus ACM model + add DenyAll mock` — `packages/contracts/test/endure/RBACSeparation.t.sol`, `packages/contracts/src/endure/DenyAllAccessControlManager.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T18**: `test(endure): port IRM params + mock alpha + wtao tests` — `packages/contracts/test/endure/EnduRateModelParams.t.sol`, `packages/contracts/test/endure/MockAlpha.t.sol`, `packages/contracts/test/endure/WTAO.t.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T19**: `test(endure): port solvency invariant + handler to venus` — `packages/contracts/test/endure/invariant/InvariantSolvency.t.sol`, `packages/contracts/test/endure/invariant/handlers/EndureHandler.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T20**: `test(venus): prove CF/LT separation` — `packages/contracts/test/endure/venus/LiquidationThreshold.t.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T21**: `test(venus): prove CF ordering rejections (oracle + LT<CF)` — `packages/contracts/test/endure/venus/CollateralFactorOrdering.t.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T22**: `test(venus): prove borrowCap=0 disables borrowing` — `packages/contracts/test/endure/venus/BorrowCapSemantics.t.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T22b**: `test(venus): prove RewardFacet rewards path is fully usable when enabled` — `packages/contracts/test/endure/venus/RewardFacetEnable.t.sol`, `packages/contracts/src/endure/MockXVS.sol`, `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T23**: `refactor(test): rename spike to Lifecycle + extract facet cut to helper` — `packages/contracts/test/endure/venus/Lifecycle.t.sol` (renamed from `VenusDirectLiquidationSpike.t.sol`), `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T24**: `refactor(test): delete obsolete MockPriceOracle test + finalize mapping` — `packages/contracts/test/endure/MockPriceOracle.t.sol` (deleted), `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`
- **T25**: `chore(venus): vendor + patch 3 broken harness files for dual-toolchain compile` — `packages/contracts/src/test-helpers/venus/VRTConverterHarness.sol` (NEW with patched import), `packages/contracts/src/test-helpers/venus/VRTVaultHarness.sol` (NEW with patched import), `packages/contracts/src/test-helpers/venus/XVSVestingHarness.sol` (NEW with patched import), `packages/contracts/FORK_MANIFEST.md` (Section 6.2 records the 3-line deviation)
- **T25b**: `chore(hardhat): solve venus test+deploy path mapping (foundation for wave 4)` — `packages/contracts/hardhat.config.ts`, `packages/contracts/tests/hardhat/README.md`
- **T25c**: `chore(deps): resolve venusprotocol package git commit SHAs for stance b audit` — `packages/contracts/lib/venusprotocol-governance-contracts/VENDOR.md`, `packages/contracts/lib/venusprotocol-oracle/VENDOR.md`, `packages/contracts/lib/venusprotocol-protocol-reserve/VENDOR.md`, `packages/contracts/lib/venusprotocol-solidity-utilities/VENDOR.md`, `packages/contracts/lib/venusprotocol-token-bridge/VENDOR.md`, `packages/contracts/FORK_MANIFEST.md`
- **T26**: `test(hardhat): vendor venus comptroller/diamond fixtures green` — `packages/contracts/tests/hardhat/Comptroller/**`, `packages/contracts/tests/hardhat/Diamond/**` (if separate dir; else folded into Comptroller), `packages/contracts/deploy/**` adaptations as needed (NO new Endure fixtures per Wave 4 anti-creep rule)
- **T27**: `test(hardhat): vendor venus unitroller fixtures green` — `packages/contracts/tests/hardhat/Unitroller/**`, `packages/contracts/deploy/**` adaptations as needed
- **T28**: `test(hardhat): vendor venus vtoken fixtures (immutable+delegate+delegator) green` — `packages/contracts/tests/hardhat/VToken/**`, `packages/contracts/deploy/**` adaptations as needed
- **T29**: `test(hardhat): vendor venus IRM fixtures green` — `packages/contracts/tests/hardhat/InterestRateModels/**`
- **T30**: `test(hardhat): vendor venus VAI fixtures (hardhat-only) green` — `packages/contracts/tests/hardhat/VAI/**`, `packages/contracts/deploy/**` adaptations as needed
- **T31**: `test(hardhat): vendor venus Prime fixtures green` — `packages/contracts/tests/hardhat/Prime/**`, `packages/contracts/deploy/**` adaptations as needed
- **T32**: `test(hardhat): vendor venus XVS fixtures green` — `packages/contracts/tests/hardhat/XVS/**`, `packages/contracts/deploy/**` adaptations as needed
- **T33**: `test(hardhat): vendor venus VRT fixtures green` — `packages/contracts/tests/hardhat/VRT/**`, `packages/contracts/deploy/**` adaptations as needed
- **T34**: `test(hardhat): vendor venus liquidator fixtures (hardhat-only) green` — `packages/contracts/tests/hardhat/Liquidator/**`, `packages/contracts/deploy/**` adaptations as needed
- **T35**: `test(hardhat): vendor venus DelegateBorrowers fixtures green` — `packages/contracts/tests/hardhat/DelegateBorrowers/**`, `packages/contracts/deploy/**` adaptations as needed
- **T36**: `test(hardhat): vendor venus swap fixtures green` — `packages/contracts/tests/hardhat/Swap/**`, `packages/contracts/deploy/**` adaptations as needed
- **T37**: `test(hardhat): vendor venus lens/utils/admin fixtures green; skip BNB-specific` — `packages/contracts/tests/hardhat/Lens/**`, `packages/contracts/tests/hardhat/Utils/**`, `packages/contracts/tests/hardhat/Admin/**` (excluding VBNB + VBNBAdmin tests, which go to SKIPPED.md via T38)
- **T38**: `docs(test): add hardhat skip list + ci verifier` — `packages/contracts/tests/hardhat/SKIPPED.md` (NEW), `scripts/check-hardhat-skips.sh` (NEW), `.github/workflows/ci.yml`
- **T39**: `ci(contracts): add hardhat test gate` — `.github/workflows/ci.yml`
- **T40**: `ci(stance-b): extract audit script + repoint to venus pin 6400a067` — `packages/contracts/.upstream-sha`, `.github/workflows/ci.yml`, `scripts/check-stance-b.sh` (NEW, mandatory)
- **T41**: `chore(scripts): rewrite e2e-smoke for venus` — `scripts/e2e-smoke.sh`
- **T42**: `chore(scripts): update forbidden-patterns for moonwell remnants` — `scripts/check-forbidden-patterns.sh`
- **T43**: `chore(snapshot): rebaseline gas-snapshot for venus` — `packages/contracts/.gas-snapshot`, `scripts/gas-snapshot-check.sh` (tolerance commentary if changed)
- **T44**: `ci(contracts): wire e2e-smoke for venus deploy` — `.github/workflows/ci.yml`
- **T45**: `feat(contracts): delete moonwell chassis (CI RED EXPECTED on this commit)` — Commit A
- **T46**: `feat(contracts): mass-move venus-staging to src + import path updates (B1 of 2)` — Commit B1 (Foundry may stay RED; Hardhat + Stance B green)
- **T46b**: `refactor(contracts): teardown dual-helper — rename to canonical names (B2 of 2)` — Commit B2 (Foundry GREEN restored; full CI green end-to-end)
- **T47–T51**: one commit per doc rewrite. Specifically:
  - **T47**: `docs(contracts): rewrite README for venus chassis` — `packages/contracts/README.md`
  - **T48**: `docs(contracts): rewrite UPSTREAM for venus pin + mark stale brief superseded` — `packages/contracts/UPSTREAM.md`, `docs/briefs/phase-0.5-venus-rebase-brief.md`
  - **T49**: `docs(contracts): finalize FORK_MANIFEST for steady-state venus layout` — `packages/contracts/FORK_MANIFEST.md`
  - **T50**: `docs(skill): update endure-architecture for venus` — `skills/endure-architecture/SKILL.md`
  - **T51**: `docs: update root README + venus footguns` — `README.md`
- **Final integration**:
  1. **Tag the planning-time `main` HEAD as `phase-0-moonwell-final`** (captured at planning time: `de5238ef41f38fa11db000ee899f0f102c5f19e5`). Command: `git tag phase-0-moonwell-final de5238ef41f38fa11db000ee899f0f102c5f19e5`. This archives the last known-good Moonwell state regardless of what `main` looks like at merge time.
  2. **Pre-merge SCENARIO CHECK** — at squash-merge time, run `git rev-parse main` and compare against `de5238ef41f38fa11db000ee899f0f102c5f19e5`:
     - **Scenario A — `main` unchanged since planning** (HEAD == `de5238ef...`): proceed directly to step 3. The tag and merge base coincide.
     - **Scenario B — `main` advanced with linear unrelated work** (HEAD ≠ planning SHA, but `git merge-base main de5238ef...` == `de5238ef...`, i.e., the planning SHA is still in main's history): proceed to step 3. The tag points at a historical commit reachable from current `main` — perfectly fine. The squash-merge will base on current `main`, naturally including any unrelated work that landed in between.
     - **Scenario C — `main` was force-pushed or rewritten** (planning SHA NOT in current `main`'s history): HALT. Either the operator force-pushed `main` (a violation of normal workflow) or someone rebased it. Re-evaluate: the tag would still be valid on the dangling commit but unreachable from `main`. Decision required from human reviewer — either (a) push the dangling commit explicitly to remote and accept the unreachable archival tag, or (b) abandon the planning-time SHA and tag at the actual merge base instead, documenting in the v0.5.0-venus commit body that `phase-0-moonwell-final` was rebased to `<new SHA>` due to upstream `main` rewrite.
  3. **Squash-merge** `phase-0.5-venus-rebase` into `main` with title `phase 0.5: venus core pool rebase` and body summarizing all 6 chunks. If `phase-0.5-venus-rebase` is behind current `main`, rebase or merge `main` into it FIRST so the squash-merge applies cleanly without conflicts.
  4. **Tag the squash-merge commit as `v0.5.0-venus`**: `git tag v0.5.0-venus` (or `git tag v0.5.0-venus <merge-commit-SHA>` if HEAD has moved).
  5. **Push both tags**: `git push origin phase-0-moonwell-final v0.5.0-venus`.

**Pre-commit checks** (each commit):
- `forge build --root packages/contracts` exits 0 (except T45 commit A which is RED-by-design)
- `forge test --root packages/contracts` exits 0 (except T45 and within-chunk WIP commits)
- For T46 onward: `pnpm --filter @endure/contracts hardhat compile` exits 0
- For PR-completion commits: full CI green

---

## Success Criteria

### Verification Commands

```bash
# Foundry side
forge build --root packages/contracts                                 # Expected: exit 0, no compiler errors
forge test --root packages/contracts -v                               # Expected: all tests pass
forge test --root packages/contracts --match-path test/endure/invariant -vvv  # Expected: 1000 runs × 50 depth, no invariant violation

# Hardhat side
pnpm --filter @endure/contracts hardhat compile                       # Expected: exit 0
pnpm --filter @endure/contracts hardhat test                          # Expected: all 37 non-fork tests pass

# Anvil + smoke
anvil --port 8545 &
ANVIL_PID=$!
forge script packages/deploy/src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast  # Expected: deployment succeeds
scripts/e2e-smoke.sh                                                  # Expected: exit 0
kill $ANVIL_PID

# Audits
scripts/check-forbidden-patterns.sh                                   # Expected: no Moonwell remnants in src/
.github/workflows/ci.yml's stance-b-audit logic, run locally          # Expected: every src/ file matches pinned Venus 6400a067
scripts/check-test-mapping.sh                                         # Expected: every deleted Phase 0 test has a mapping row
scripts/gas-snapshot-check.sh                                         # Expected: within tolerance vs new Venus baseline

# State
test ! -d packages/contracts/src/venus-staging                        # Expected: directory does not exist
test ! -e packages/contracts/src/Comptroller.sol                      # Expected: Moonwell file gone
test ! -e packages/contracts/src/MToken.sol                           # Expected: Moonwell file gone
test ! -e packages/contracts/src/endure/MockPriceOracle.sol           # Expected: replaced by ResilientOracle
test -e packages/contracts/src/endure/MockResilientOracle.sol         # Expected: present

# Git
git tag --list phase-0-moonwell-final                                 # Expected: tag exists (pre-merge main archival)
git tag --list v0.5.0-venus                                           # Expected: tag exists (post-merge Venus genesis)
git log main --oneline -1                                             # Expected: HEAD is the squash-merge commit
```

### Final Checklist

- [ ] All 21 spec final-state success criteria hold (see Definition of Done above)
- [ ] All Must Haves implemented
- [ ] All Must NOT Haves absent (verified by forbidden-pattern + Stance B + scope-fidelity F4)
- [ ] All 55 tasks complete with evidence files in `.sisyphus/evidence/` (T1–T51 + T22b + T25b + T25c + T46b)
- [ ] F1–F4 all APPROVE
- [ ] User's explicit "okay" recorded before squash-merge
- [ ] Tags `phase-0-moonwell-final` (pre-merge `main`) AND `v0.5.0-venus` (post-merge squash commit) both created and pushed to remote
- [ ] Squash-merge complete; PR closed; branch optionally deleted
