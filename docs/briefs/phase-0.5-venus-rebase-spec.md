# Endure Network — Phase 0.5 Venus Rebase Spec

## Status

**Active spec.** Consolidates and supersedes the previous draft of this file plus `docs/briefs/phase-0.5-venus-rebase-brief.md`. The brief is retained as historical Stage A evidence and is no longer authoritative for execution.

This spec is the single source of truth for the Phase 0.5 rebase. It defines what gets built, in what order, with what guardrails, and what "done" means. Implementation does not start until this spec is approved. The implementation plan in `.sisyphus/plans/phase-0.5-venus-rebase.md` will be regenerated from this spec via the writing-plans skill after approval.

## Context

Endure Phase 0 shipped a Moonwell v2 Foundry fork with local Anvil deployment, mock alpha collateral, mock WTAO borrow market, integration tests, invariant coverage, gas snapshot CI, Stance B byte-identical audit discipline, and live-chain smoke validation. The Phase 0 codebase is disciplined: byte-identical to Moonwell `8d5fb1107babf7935cfabc2f6ecdb1722547f085`, with a small Endure-authored surface (mocks + deploy helper + test suites totaling ~111 LOC of source plus ~854 LOC of tests).

Phase 0.5 changes the lending chassis from Moonwell v2 to Venus Protocol Core Pool so Endure inherits Venus's audited support for separate `collateralFactorMantissa` and `liquidationThresholdMantissa`. This is a safety decision: do not hand-roll health-factor or liquidation-threshold math in a money market when audited Venus code already implements the feature.

Locked Endure architecture remains unchanged except the chassis:
- TAO-only borrow asset.
- Alpha markets are collateral-only.
- Pooled multi-collateral account health.
- Foundry as the primary on-chain tooling, with Hardhat added side-by-side for upstream test validation.
- pnpm workspace monorepo.
- Deployer EOA/admin for Phase 0.5; governance remains deferred.
- No Bittensor precompile integration in Phase 0.5.

## Upstream pin

Use Venus Protocol commit:

```text
6400a067114a101bd3bebfca2a4bd06480e84831
```

Reference tag: `v10.2.0-dev.5`.

**Rationale:**

- `v10.2.0-dev.5` is functionally identical to `v10.2.0-dev.4` for our purposes: `git diff v10.2.0-dev.4 v10.2.0-dev.5 -- contracts/` is empty. The version bump only added audit PDFs.
- Both tags include the March 20, 2026 donation-attack patch merge (PR #664) audited by Quantstamp, Certik, and Hashdit.
- Older `v10.1.0` predates the fix and is not acceptable.
- Endure's Stage A spike was executed against this exact HEAD commit, so the pin matches the executed evidence.
- `dev.5` is the operationally reproducible commit with no contract drift vs `dev.4`.

## Decision summary

The 15 decisions locked during the brainstorm phase of this spec are summarized here for executor reference. Every section below derives from this table.

| # | Decision |
|---|---|
| 1 | Stage A is currently YELLOW, not GREEN. Tighten it inside the Endure repo as Task 0 before Stage B. |
| 2 | Vendor the full Venus `contracts/` tree byte-identical; let Foundry tree-shake at compile time. |
| 3 | Stance B audits ALL vendored Venus files byte-identically against pinned commit `6400a067`. |
| 4 | Toolchain: Foundry + Hardhat side-by-side in `packages/contracts/`. Foundry is canonical for Endure deployment and tests; Hardhat hosts vendored upstream Venus tests. |
| 5 | Final layout: Venus mirrors upstream directly under `packages/contracts/src/`. No `/venus/` subfolder. Endure-authored stays in `src/endure/`. |
| 6 | Rebase sequencing: stage Venus files in `src/venus-staging/` during the rebase, then mass-move + delete-Moonwell in the final two commits. CI stays green throughout. |
| 7 | `MockResilientOracle.sol` (Endure-authored, in `src/endure/`) implements full `ResilientOracleInterface` with admin-set per-vToken prices. Replaces Phase 0's `MockPriceOracle`. |
| 8 | Alpha markets default to CF = 0.25e18, LT = 0.35e18 (10% gap). |
| 9 | ProtocolShareReserve: deploy a no-op mock only when a tested runtime path requires it. |
| 10 | RewardFacet: deployed and registered in the diamondCut from day one with all reward speeds zero. |
| 11 | All Endure Foundry tests are ported with mandatory behavior-mapping table discipline. |
| 12 | All 37 non-fork Venus Hardhat tests are ported and green; fork tests are skipped. VAI/Prime/XVS/Liquidator/Swap test-fixture infrastructure is accepted as a scope expansion. |
| 13 | Pin: `6400a067` / `v10.2.0-dev.5`. |
| 14 | Stage A spike code lives at `packages/contracts/test-foundry/VenusDirectLiquidationSpike.t.sol`. |
| 15 | Anvil deployment uses `forge script` (canonical); Hardhat fixtures use `hardhat-deploy`. Branch: long-lived `phase-0.5-venus-rebase` with per-chunk PRs, single squash-merge to main with archival tag `moonwell-v0.1.0`. |

## Stage A re-verdict

The original brief declared Stage A GREEN based on a spike test (`VenusDirectLiquidationSpike.t.sol`) executed in a temporary workspace at `/var/folders/zc/.../venus-protocol`. Direct inspection of that spike against the spec's 8 hard gates produces a more honest verdict: **YELLOW**, not GREEN.

### What the spike actually proved

- Foundry compiles Venus minimum core under solc 0.8.25 / cancun.
- Diamond instantiates and `_setPendingImplementation` + `_become` succeed.
- `diamondCut` registers MarketFacet, SetterFacet, PolicyFacet selectors and `facetAddress` lookups resolve correctly.
- Direct vToken liquidation (`liquidateBorrow`) works when `liquidatorContract == address(0)`. This is the novel mechanic the spike was specifically designed to validate, and it works.
- Markets supplied, borrowed, and liquidated successfully.
- `setCollateralFactor(VToken, CF, LT)` accepts CF + LT pairs.

### What the spike did NOT prove

The spike used `ComptrollerMock` for the lifecycle and liquidation flow, NOT the Unitroller + Diamond proxy chain. As a result:

- The Diamond deployment gate is only partially proven: the Diamond exists and selectors register, but markets, oracle, and lifecycle calls bypass it.
- The Mock boundary gate is partially proven: the spike used `SimplePriceOracle` (Venus-vendored test oracle), not a `ResilientOracleInterface`-conformant mock.
- The Market deployment gate is partially proven: vWTAO and vAlpha deploy against `ComptrollerMock`, not against an Unitroller-routed Comptroller.
- The Lifecycle gate is partially proven: supply → borrow is exercised; full repay and redeem are NOT exercised.
- The CF/LT semantics gate is partially proven: setting CF and LT succeeds; the rejection path for `LT < CF` is NOT explicitly tested.

### Coverage table

| # | Hard gate | Spike status |
|---|---|---|
| 1 | Foundry compile gate | GREEN |
| 2 | Diamond deployment gate | YELLOW (selectors only; not lifecycle-routed) |
| 3 | Selector registration gate | GREEN |
| 4 | Mock boundary gate | YELLOW (SimplePriceOracle; not ResilientOracleInterface) |
| 5 | Market deployment gate | YELLOW (against ComptrollerMock; not Unitroller proxy) |
| 6 | Lifecycle gate | YELLOW (supply + borrow only; no repay/redeem) |
| 7 | Liquidation gate | GREEN |
| 8 | CF/LT semantics gate | YELLOW (no LT<CF rejection test) |

### Implication for execution

Stage B does NOT begin until Stage A is GREEN end-to-end inside the Endure repository. Closing the five YELLOW gates is **Task 0** of this spec. Once Task 0 is GREEN, Stage B becomes a mechanical port instead of a combined "spike + rebase" effort, which substantially reduces risk.

## Task 0: Tightened Stage A

Task 0 lives in the Endure repository at `packages/contracts/test-foundry/`. This is a new top-level test directory inside the contracts package, distinct from `packages/contracts/test/` which holds steady-state tests. The directory contains only Stage A artifacts.

### Goal

Close the five YELLOW gates from the coverage table above, all inside `forge-lending`, all reachable via `forge test --root packages/contracts`.

### Required test file

`packages/contracts/test-foundry/VenusDirectLiquidationSpike.t.sol`

This file is a tightened version of the original spike. It must:

1. Use Unitroller + Diamond + MarketFacet + SetterFacet + PolicyFacet + ComptrollerLens (NOT `ComptrollerMock`).
2. Wire markets, oracle, ACM, and lens through the Unitroller-routed proxy.
3. Use a Venus-shaped mock ACM (`AllowAllAccessControl` implementing `IAccessControlManagerV8.isAllowedToCall`).
4. Use a Venus-shaped mock oracle implementing `ResilientOracleInterface` (the same `MockResilientOracle` that will become the Endure-authored mock under `src/endure/`).
5. Deploy `VBep20Immutable` markets for a mock WTAO and mock alpha underlyings.
6. Use `TwoKinksInterestRateModel`.

### Required tests

Each test below maps directly to a YELLOW gate from the coverage table.

| Test | Gate closed |
|---|---|
| `test_DiamondRoutesLifecycleThroughUnitroller` | Gate 2 (Diamond deployment) |
| `test_ResilientOracleMockSatisfiesPriceReads` | Gate 4 (Mock boundary) |
| `test_VBep20MarketsDeployAgainstUnitrollerProxy` | Gate 5 (Market deployment) |
| `test_FullLifecycleSupplyBorrowRepayRedeem` | Gate 6 (Lifecycle) |
| `test_SetCollateralFactorRejectsLTBelowCF` | Gate 8 (CF/LT semantics) |
| `test_DirectVTokenLiquidationWorksWhenLiquidatorContractUnset` | Gate 7 (preserved from original spike) |
| `test_DiamondRegistersRequiredCoreSelectors` | Gate 3 (preserved from original spike) |

### Vendoring required for Task 0

To support Task 0, the Venus contracts/ tree must be vendored into `src/venus-staging/` and the Endure-authored `MockResilientOracle.sol` plus `AllowAllAccessControlManager.sol` mocks must exist under `src/endure/`. Foundry config must be bumped to solc 0.8.25 / cancun. See section "Vendoring & layout" below.

### Stage A verdict

Stage A is GREEN if and only if:

1. All seven tests in `VenusDirectLiquidationSpike.t.sol` pass.
2. `forge test --root packages/contracts` exits 0 with the existing Phase 0 Moonwell tests still green (Moonwell chassis is still live during Task 0; the staging tree co-exists with it).
3. The `FORK_MANIFEST.md` and `UPSTREAM.md` are updated to declare the Venus pin alongside the existing Moonwell pin (Stage A acknowledges the dual-vendor intermediate state).

If any test fails, Task 0 is RED and Stage B does not start. The team decides whether to fix the failure, revise the spec, or abort.

After Task 0 GREEN, the file is preserved. Stage B Task 4 will rename and fold it into `test/endure/venus/Lifecycle.t.sol` (or similar) as part of the steady-state test suite.

## Vendoring & layout

### Final steady-state layout

After Stage B completes, `packages/contracts/src/` mirrors Venus upstream's `contracts/` directory structure 1:1. Endure-authored code lives in `src/endure/`. The `Comptroller.sol` Moonwell file is replaced by Venus's `Comptroller/` directory. Examples:

```text
packages/contracts/src/
├── Comptroller/
│   ├── ComptrollerInterface.sol
│   ├── ComptrollerStorage.sol
│   ├── Diamond/
│   │   ├── Diamond.sol
│   │   ├── facets/
│   │   │   ├── FacetBase.sol
│   │   │   ├── MarketFacet.sol
│   │   │   ├── PolicyFacet.sol
│   │   │   ├── RewardFacet.sol
│   │   │   └── SetterFacet.sol
│   │   └── interfaces/
│   │       └── IDiamondCut.sol
│   └── Unitroller.sol
├── Tokens/
│   └── VTokens/
│       ├── VBep20.sol
│       ├── VBep20Immutable.sol
│       └── VToken.sol
├── InterestRateModels/
│   ├── InterestRateModelV8.sol
│   └── TwoKinksInterestRateModel.sol
├── Lens/
│   └── ComptrollerLens.sol
├── Oracle/
│   └── ResilientOracleInterface.sol
├── ... (full Venus contracts/ tree, including VAI/Prime/XVS/Liquidator/Swap)
└── endure/
    ├── EnduRateModelParams.sol
    ├── EndureRoles.sol
    ├── MockAlpha30.sol
    ├── MockAlpha64.sol
    ├── MockResilientOracle.sol      [NEW: replaces MockPriceOracle.sol]
    ├── AllowAllAccessControlManager.sol  [NEW]
    └── WTAO.sol
```

Phase 0's `src/MockPriceOracle.sol` is deleted. Phase 0's Moonwell files (`Comptroller.sol`, `MToken.sol`, `MErc20.sol`, etc.) are deleted in the same final commit that does the staging-to-`src/` move. Phase 0's `src/rewards/` directory is deleted; Venus does not need it.

### Rebase-time staging layout

During the rebase (all of Task 0 plus Stage B Tasks 1–7), Venus is vendored under `src/venus-staging/`. Both chassis live side-by-side:

```text
packages/contracts/src/
├── Comptroller.sol           [Moonwell, still live]
├── ComptrollerInterface.sol  [Moonwell, still live]
├── MToken.sol                [Moonwell, still live]
├── ...
├── venus-staging/
│   ├── Comptroller/
│   │   ├── Diamond/...
│   │   └── Unitroller.sol
│   ├── Tokens/VTokens/...
│   └── ... (full Venus tree)
└── endure/
    └── ...
```

This sidesteps the unavoidable path collision (Moonwell's flat `Comptroller.sol` file vs Venus's nested `Comptroller/` directory). CI stays green throughout Stage B because both chassis compile and test independently.

The penultimate commit of Stage B deletes all Moonwell `.sol` files. The final commit does:

```bash
git mv src/venus-staging/* src/
rmdir src/venus-staging
# Update all import paths in tests and src/endure/ from
#   "@protocol/venus-staging/Comptroller/..." to "@protocol/Comptroller/..."
# Update Stance B audit script's path mapping.
# Update FORK_MANIFEST.md.
```

After this commit, the steady-state layout above is reached.

### What gets vendored

The full Venus `contracts/` tree at commit `6400a067` is copied verbatim into `src/venus-staging/`. This includes:

- Comptroller core (Comptroller, Unitroller, Diamond, all facets, ComptrollerLens, storage).
- Token layer (VToken, VBep20, VBep20Immutable, VBep20Delegate, VBep20Delegator, VBNB).
- Interest rate models (TwoKinksInterestRateModel, InterestRateModelV8, JumpRateModel variants).
- Oracle interfaces (ResilientOracleInterface, etc.).
- Access control interfaces (IAccessControlManagerV8).
- VAI subsystem (VAIController, VAIVault, VAI token, PegStability, etc.) — vendored, not deployed by Endure.
- Prime subsystem (Prime, PrimeLiquidityProvider) — vendored, not deployed by Endure.
- XVS / VRT subsystem (XVSVault, XVSStore, XVS, VRTVault, VRTConverter, VRT) — vendored, not deployed by Endure.
- External Liquidator — vendored, not deployed by Endure.
- DelegateBorrower contracts — vendored, not deployed by Endure.
- SwapRouter — vendored, not deployed by Endure.
- All test/ helpers from Venus's `contracts/test/` (e.g., MockToken, SimplePriceOracle, ComptrollerMock) needed by upstream Hardhat tests — vendored under `src/test-helpers/venus/` (NOT under `src/test/`, to avoid collision with Endure's own `test/` directory).

The vendored tree is byte-identical to upstream. Foundry's compilation graph will only compile the subset reachable from Endure's deploy helper and tests; the unused VAI/Prime/XVS/etc. files compile only when Hardhat references them.

### Solc and EVM target

`foundry.toml` and `hardhat.config.ts` both target solc 0.8.25 with `evm_version = "cancun"`. Venus vendored files include some legacy 0.5.16 sources (notably VAI controller and parts of XVS vault). The Hardhat config registers both 0.5.16 and 0.8.25 compilers. Foundry's config registers 0.8.25 as the default and uses per-file pragma overrides for 0.5.16 sources via `[profile.default.solc_versions]`-equivalent path mapping.

Foundry's tree-shake means 0.5.16 sources only compile if reachable from a Foundry test. Endure's Foundry tests do not import them, so in practice the Foundry build only sees 0.8.25.

### Remappings

Updated `packages/contracts/remappings.txt`:

```text
@forge-std/=lib/forge-std/src/
@openzeppelin-contracts/=lib/openzeppelin-contracts/
@openzeppelin/=lib/openzeppelin-contracts/
@openzeppelin-contracts-upgradeable/=lib/openzeppelin-contracts-upgradeable/
@protocol/=src/
@test/=test/
@test-foundry/=test-foundry/
@utils/=src/utils/
@script/=script/
@venusprotocol/access-control-contracts/=lib/access-control-contracts/
@venusprotocol/governance-contracts/=lib/governance-contracts/
@venusprotocol/oracle/=lib/oracle/
@venusprotocol/solidity-utilities/=lib/solidity-utilities/
```

The `@venusprotocol/*` remappings handle Venus's external dependency packages. Each is vendored as a git submodule under `lib/` (matching Phase 0's `lib/openzeppelin-contracts/` pattern), pinned to the same commit Venus's package.json declares at `6400a067`.

### Stance B audit posture

Stance B byte-identity is enforced for the entire vendored Venus tree (not just the deployed subset). The audit script:

1. Clones `VenusProtocol/venus-protocol` at commit `6400a067` into a CI temp directory.
2. For each `.sol` file under `packages/contracts/src/` whose path does NOT start with `endure/`, computes SHA256 and compares to the corresponding file in the Venus checkout at the path-mapped equivalent.
3. Path mapping in steady state: `packages/contracts/src/Foo/Bar.sol` ↔ `<venus>/contracts/Foo/Bar.sol`. During staging: `packages/contracts/src/venus-staging/Foo/Bar.sol` ↔ same upstream.
4. For `.sol` files in the Venus checkout that have NO corresponding file in Endure (i.e., Endure didn't vendor them), the audit logs a "vendoring gap" warning but does not fail.
5. For `.sol` files in Endure that have NO upstream equivalent (and aren't under `src/endure/`), the audit fails. This catches accidental modifications.
6. For files explicitly listed as "documented deviations" in `FORK_MANIFEST.md`, the audit verifies the deviation note exists and skips the byte check.

The Venus dependency packages under `lib/` (`@venusprotocol/*`) are each audited the same way against their own pinned commits (recorded in `FORK_MANIFEST.md`).

`src/endure/` is exempt from byte-identity audit (Endure-authored). Files there are subject to a separate "no Moonwell remnants" forbidden-pattern scan.

`src/test-helpers/venus/` (Venus's `contracts/test/` files, vendored to support Hardhat tests) is audited against `<venus>/contracts/test/`.

### FORK_MANIFEST.md regeneration

Phase 0's `FORK_MANIFEST.md` documents Moonwell deviations. It is rewritten in the final cleanup commit to document Venus deviations. The new manifest contains:

- Pinned upstream: `VenusProtocol/venus-protocol` commit `6400a067`, tag `v10.2.0-dev.5`.
- Pinned dependency commits for each `@venusprotocol/*` package under `lib/`.
- Section: "Files vendored byte-identical" (full path list under `src/`).
- Section: "Files vendored byte-identical from Venus test/" (under `src/test-helpers/venus/`).
- Section: "Endure-authored files" (under `src/endure/`).
- Section: "Documented deviations" — expected to be empty at Stage B completion. Any non-empty entry requires a Stance B exception note.
- Section: "Files explicitly NOT vendored" — empty if the full-tree vendor decision holds.

`UPSTREAM.md` is rewritten similarly to point at Venus instead of Moonwell.

`.upstream-sha` is rewritten from `8d5fb1107babf7935cfabc2f6ecdb1722547f085` to `6400a067114a101bd3bebfca2a4bd06480e84831`.

## Toolchain

`packages/contracts/` runs both Foundry and Hardhat. Each tool owns a distinct concern:

- **Foundry** (canonical for Endure): builds Endure-deployed contracts, runs Endure's Foundry test suite, runs invariant fuzzing, produces gas snapshots, drives Anvil deployment via `forge script`. CI's `forge test` job is the primary correctness gate for Endure.
- **Hardhat**: hosts vendored Venus upstream tests under `tests/hardhat/`. Runs upstream Venus's hardhat-deploy fixtures to set up Comptroller / VAI / Prime / XVS / Liquidator state needed by those tests. `hardhat test` is a secondary correctness gate proving the vendored Venus contracts behave per-upstream.

### Files added to `packages/contracts/`

- `hardhat.config.ts` — pins solc 0.8.25 and 0.5.16, points at `tests/hardhat/`, registers `hardhat-deploy`, configures the dual-network setup for upstream test fixtures.
- `tsconfig.json` — TypeScript config for Hardhat tests.
- `package.json` (modify) — add `hardhat`, `hardhat-deploy`, `@nomicfoundation/hardhat-toolbox`, `ethers`, `chai`, plus dev dependencies matching Venus upstream.
- `tests/hardhat/` — vendored from Venus's `tests/hardhat/`, Fork tests removed.
- `deploy/` — vendored from Venus's `deploy/` directory (used by Hardhat fixtures only, NOT by Endure's Anvil deployment).
- `.gitignore` (modify) — add `artifacts/`, `cache_hardhat/`, `deployments/localhost/` (Hardhat byproducts).

### Foundry remains primary

- Endure's `DeployLocal.s.sol` stays as the canonical Anvil deployment entrypoint.
- `e2e-smoke.sh` remains a Foundry-driven script.
- The gas snapshot at `.gas-snapshot` is a Foundry artifact only.
- The invariant test (1000 runs × 50 depth) is Foundry-only.
- Phase 0's CI jobs `contracts-build`, `contracts-test`, `e2e-smoke`, `forbidden-patterns`, and `gas-snapshot-check` remain Foundry-driven, repointed at Venus contracts.

### Hardhat is additive

- `hardhat compile` runs as part of CI but is allowed to compile a superset of files (Venus's full vendored surface, including 0.5.16 sources).
- `hardhat test` runs the 37 non-fork Venus tests, with hardhat-deploy fixtures setting up VAI/Prime/XVS/Liquidator/etc.
- `hardhat-deploy` artifacts are written to `packages/contracts/deployments/hardhat/` and are NOT consumed by Endure's Anvil deployment.

### State separation

Foundry and Hardhat never share deployment state. Endure's Anvil deployment is one universe; Hardhat's test fixtures are another. The two CI jobs run in parallel.

## Task 0 in detail

Task 0 is the closure of Stage A inside the Endure repo. It produces the artifacts needed for Stage B to begin.

### Deliverables

1. `packages/contracts/foundry.toml` updated to solc 0.8.25 + evm_version cancun.
2. `packages/contracts/remappings.txt` updated with new mappings.
3. `packages/contracts/src/venus-staging/` populated with the full vendored Venus tree at commit `6400a067`.
4. `packages/contracts/lib/` git submodules added for `@venusprotocol/*` dependencies, pinned.
5. `packages/contracts/src/endure/MockResilientOracle.sol` implementing `ResilientOracleInterface`.
6. `packages/contracts/src/endure/AllowAllAccessControlManager.sol` implementing `IAccessControlManagerV8`.
7. `packages/contracts/test-foundry/VenusDirectLiquidationSpike.t.sol` containing all seven tests listed in the Stage A re-verdict section.
8. `packages/contracts/FORK_MANIFEST.md` updated to declare the Venus pin in addition to the still-live Moonwell pin (intermediate dual-vendor state).
9. `packages/contracts/UPSTREAM.md` updated similarly.
10. `.github/workflows/ci.yml` updated with a new `contracts-stage-a` job that runs only the Task 0 tests.

### Acceptance criteria

- `forge test --root packages/contracts --match-path test-foundry/VenusDirectLiquidationSpike.t.sol -vvv` passes.
- `forge test --root packages/contracts` passes (Phase 0 Moonwell tests still green, since the Moonwell chassis is untouched in Task 0).
- The new CI job succeeds.
- Stance B audit passes for `src/venus-staging/` (every vendored file byte-identical to upstream).
- `forge build --root packages/contracts` succeeds with both chassis present.

### Out of scope for Task 0

- No changes to Endure's deploy helper (`EndureDeployHelper.sol` continues to deploy the Moonwell chassis).
- No changes to Endure's existing test suite under `test/endure/`.
- No Hardhat configuration yet.
- No e2e-smoke updates.
- No Moonwell deletions.

## Stage B scope

Stage B begins after Task 0 GREEN and explicit team acceptance. It is structured as four chunks delivered as one PR per chunk into `phase-0.5-venus-rebase`.

### Chunk 1: Hardhat toolchain + Venus dependencies

- Add `hardhat.config.ts`, `tsconfig.json`, update `package.json`.
- Vendor Venus's `tests/hardhat/` (non-fork only) and `deploy/` directories.
- Vendor Venus's `contracts/test/` helpers under `src/test-helpers/venus/`.
- Configure dual solc 0.8.25 + 0.5.16 in Hardhat.
- Add CI job `contracts-hardhat-build` that runs `hardhat compile`.
- Acceptance: `hardhat compile` succeeds, no tests run yet.

### Chunk 2: Endure deploy helper rewrite + Anvil deployment

- Rewrite `packages/contracts/test/helper/EndureDeployHelper.sol` to deploy Venus chassis from `src/venus-staging/`.
- Rewrite `packages/deploy/src/DeployLocal.s.sol` for Venus.
- New deploy helper produces an `Addresses` struct with: `unitroller`, `comptrollerLens`, `accessControlManager`, `resilientOracle`, `marketFacet`, `policyFacet`, `setterFacet`, `rewardFacet` (zero state), `vWTAO`, `vAlpha30`, `vAlpha64`, `irmWTAO`, `irmAlpha`, `wtao`, `mockAlpha30`, `mockAlpha64`.
- Implement the 23-step deployment sequence (deploy ACM → deploy oracle → deploy lens → deploy Unitroller → deploy Diamond impl → deploy facets → `_setPendingImplementation` → `_become` → diamondCut → set lens → set oracle → set ACM → set close factor → deploy underlyings → deploy IRMs → deploy VBep20Immutable markets → support markets → set oracle prices → set CF/LT → set liquidation incentive → set caps → enable borrow on vWTAO → seed and burn).
- CF/LT defaults: vWTAO CF=0, LT=0; vAlpha30/vAlpha64 CF=0.25e18, LT=0.35e18.
- Borrow cap: vWTAO `type(uint256).max`; vAlpha* `0` (Venus semantic: borrowing disabled).
- Oracle prices set BEFORE any nonzero CF/LT.
- Every market seeded with `1e18` units of underlying and burned to `0xdEaD`.
- ProtocolShareReserve: NOT deployed in Chunk 2. If a runtime path needs it, deploy a no-op mock and document it in `FORK_MANIFEST.md`.
- RewardFacet: deployed and registered in diamondCut. All reward speeds zero.
- Acceptance: a new test `test/endure/venus/Deploy.t.sol` passes, asserting all addresses exist, all selectors registered, all CF/LT in expected state.

### Chunk 3: Foundry test port

- Port every Phase 0 Foundry test under `test/endure/` to use the Venus deploy helper.
- Behavior-mapping table is mandatory (see "Test porting strategy" section below).
- Targeted coverage:
  - `test/endure/integration/AliceLifecycle.t.sol` — supply → borrow → repay → redeem against Venus.
  - `test/endure/integration/Liquidation.t.sol` — price-drop liquidation against Venus, plus negative paths.
  - `test/endure/SeedDeposit.t.sol` — seed-and-burn for vTokens.
  - `test/endure/RBACSeparation.t.sol` — Venus ACM-based admin/guardian separation.
  - `test/endure/invariant/InvariantSolvency.t.sol` — solvency invariant against Venus, 1000 runs × 50 depth.
  - `test/endure/invariant/handlers/EndureHandler.sol` — handler addresses + actions for Venus.
- New tests required by Venus's distinct semantics:
  - `test/endure/venus/LiquidationThreshold.t.sol` — proves CF used for borrow eligibility, LT for liquidation eligibility, in clearly distinct scenarios.
  - `test/endure/venus/CollateralFactorOrdering.t.sol` — proves `setCollateralFactor` rejects calls when oracle price is unset.
  - `test/endure/venus/BorrowCapSemantics.t.sol` — proves `borrowCap == 0` disables borrowing (semantic flip from Moonwell).
  - `test/endure/venus/DiamondSelectorRouting.t.sol` — proves all required selectors resolve to the expected facet (steady-state version of the Stage A spike test).
- The Stage A `test-foundry/VenusDirectLiquidationSpike.t.sol` is moved to `test/endure/venus/Lifecycle.t.sol` and renamed; the `test-foundry/` directory is deleted.
- Acceptance: `forge test --root packages/contracts` exits 0. The Phase 0 Moonwell-targeted tests are deleted in this chunk; the behavior-mapping table accounts for every deletion.

### Chunk 4: Hardhat test port

- Bring over all 37 non-fork Venus Hardhat tests into `packages/contracts/tests/hardhat/`.
- Bring over Venus's `deploy/` scripts and adapt fixtures to run against Hardhat's local network (NOT Anvil).
- Stub or vendor the test-fixture infrastructure for VAI/Prime/XVS/VRT/Liquidator/Swap/DelegateBorrowers as needed for the upstream tests to pass. These deployments live ONLY in Hardhat fixtures; Endure's Anvil deployment never sees them.
- Tests skipped from upstream:
  - All Fork tests under `tests/hardhat/Fork/` (BSC mainnet-fork dependencies; not portable).
  - Any test that requires a real BSC RPC endpoint or a specific BSC block height.
- Acceptance: `hardhat test` exits 0. CI runs `hardhat test` in parallel with `forge test`.

### Chunk 5: CI, smoke, docs, and final cleanup

This chunk is split across two PRs because the final cleanup commit is mechanical and risk-amplifying.

#### Chunk 5a: CI and smoke updates

- Update `.github/workflows/ci.yml`:
  - Repoint `stance-b-audit` from Moonwell `8d5fb11` to Venus `6400a067`. Audit covers `src/venus-staging/` (full byte-identity).
  - Add `contracts-hardhat-test` job.
  - Update `forbidden-patterns` to scan for stripped Moonwell identifiers (since Moonwell is being removed).
  - Update `e2e-smoke` to test Venus deployment.
- Update `scripts/e2e-smoke.sh` to:
  - Read addresses from the new Venus `addresses.json`.
  - Exercise mint → approve → enterMarkets → borrow → repay → redeem against Venus contracts.
  - Check for Venus `Failure(uint256, uint256, uint256)` events instead of Moonwell's signature.
  - Assert direct vToken liquidation works with `liquidatorContract == address(0)`.
- Update `.gas-snapshot` baseline (gas costs change substantially with Venus).

#### Chunk 5b: Mass-move + delete-Moonwell

This chunk is two atomic commits:

- **Commit A (delete Moonwell)**: delete every `.sol` under `packages/contracts/src/` whose path does NOT start with `venus-staging/` or `endure/`. Delete `src/rewards/`. Delete unused `proposals/` artifacts (Moonwell-specific). Delete `lib/` entries that are Moonwell-only. Update `FORK_MANIFEST.md` Section 5 to remove Moonwell deviation entries. CI is expected to be RED on this commit alone.
- **Commit B (move Venus to root)**: `git mv src/venus-staging/* src/`. Update every import path in `src/endure/`, `test/`, `tests/hardhat/`, `script/`, `proposals/`, and `deploy/` from `@protocol/venus-staging/...` to `@protocol/...`. Update `scripts/check-stance-b.sh` path mapping to drop the `venus-staging/` prefix. Update `FORK_MANIFEST.md` and `UPSTREAM.md` to reflect the steady-state layout.

The PR for Chunk 5b is reviewed as the union of these two commits but they are kept separate in history so reverting is mechanical.

Acceptance for Chunk 5: `forge test`, `hardhat test`, `e2e-smoke`, Stance B audit, gas snapshot, forbidden-patterns scan all green on the final commit.

### Chunk 6: Documentation

- Rewrite `packages/contracts/README.md` to describe Venus chassis, market parameters, deployment, test suites.
- Rewrite `packages/contracts/UPSTREAM.md` to declare Venus as upstream.
- Rewrite `packages/contracts/FORK_MANIFEST.md` for the steady-state Venus layout.
- Rewrite `skills/endure-architecture/SKILL.md` to reflect Venus-based architecture.
- Update root `README.md` references.
- Document Venus-specific footguns: CF/LT ordering, cap semantics, Diamond selectors, ComptrollerLens criticality, RewardFacet inclusion rationale.

## Test porting strategy

### Foundry side: behavior-mapping table

Every Phase 0 Endure Foundry test must be either ported or replaced. Before deleting any Phase 0 test, the porter MUST add a row to `docs/briefs/phase-0.5-venus-rebase-test-mapping.md` (a new file created in Chunk 3):

| Phase 0 test path | Behavior asserted | Venus replacement test path | Notes |
|---|---|---|---|
| `test/endure/integration/AliceLifecycle.t.sol::test_AliceCanSupplyBorrowRepayRedeem` | Single-account full lifecycle on alpha collateral and WTAO borrow | `test/endure/integration/AliceLifecycle.t.sol::test_AliceCanSupplyBorrowRepayRedeem` (rewritten) | CF/LT semantics applied |
| `test/endure/integration/Liquidation.t.sol::test_PriceDropMakesAccountLiquidatable` | Oracle price drop creates shortfall | `test/endure/integration/Liquidation.t.sol::test_PriceDropMakesAccountLiquidatable` | Uses LT (not CF) for liquidation threshold |
| ... | ... | ... | ... |

CI enforces this with a script `scripts/check-test-mapping.sh` that runs in the `contracts-test` job: for every Phase 0 test path absent from the current tree, a corresponding row must exist in the mapping file. Missing rows fail CI.

The mapping file is a deliverable of Chunk 3. It is not generated by the spec — the porter authors it as part of the port.

Required preserved behaviors (must each have a mapping row):

- Alice can supply alpha, borrow WTAO, repay, and redeem.
- Oracle price drop makes an account liquidatable.
- Direct liquidation transfers seized collateral to liquidator.
- Markets start non-empty via seed-and-burn.
- Alpha markets are collateral-only (borrow disabled).
- Solvency invariant holds under handler actions.
- RBAC separation: admin, pause guardian, borrow cap guardian, supply cap guardian (Venus equivalent: ACM-gated roles).

New behaviors that did not exist in Phase 0 (no mapping row needed; net-new tests):

- LT lower than CF is rejected.
- Oracle price must be set before nonzero CF/LT.
- Direct vToken liquidation works with `liquidatorContract == address(0)`.
- Borrow cap 0 disables borrowing.
- Diamond selector routing is correct.

### Hardhat side: full upstream suite

The 37 non-fork Venus Hardhat tests are vendored into `packages/contracts/tests/hardhat/` byte-identical to upstream. Their setup fixtures use vendored Venus deploy scripts under `packages/contracts/deploy/`. To make every test pass, the corresponding upstream-Venus contracts must be deployable in the Hardhat local network:

| Test directory | Required infrastructure (deployed in Hardhat fixtures only) |
|---|---|
| `Comptroller/Diamond/` | Comptroller core (already in Endure's deploy surface) + RewardFacet + flashLoan facet (vendored, not on Endure Anvil) |
| `Unitroller/` | Unitroller (already in Endure's deploy surface) |
| `VToken/` | VBep20Immutable, VBep20Delegate, VBep20Delegator (Endure deploys Immutable; Hardhat fixtures deploy all three variants) |
| `InterestRateModels/` | TwoKinksInterestRateModel (in Endure's deploy surface) |
| `VAI/` | VAIController, VAIVault, VAI token, PegStability — Hardhat-fixture-only |
| `Prime/` | Prime, PrimeLiquidityProvider — Hardhat-fixture-only |
| `XVS/` | XVSVault, XVSStore, XVS token — Hardhat-fixture-only |
| `VRT/` | VRTVault, VRTConverter, VRT token — Hardhat-fixture-only |
| `Liquidator/` | External Liquidator contract — Hardhat-fixture-only |
| `DelegateBorrowers/` | SwapDebtDelegate, MoveDebtDelegate — Hardhat-fixture-only |
| `Swap/` | SwapRouter — Hardhat-fixture-only |
| `Admin/VBNBAdmin.ts` | VBNBAdmin — may be skipped if BNB-specific assumptions cannot be neutralized; documented in mapping file |
| `Lens/Rewards.ts` | RewardLens — Hardhat-fixture-only |
| `Utils/CheckpointView.ts` | CheckpointView — Hardhat-fixture-only |

Skipped Venus Hardhat tests (each requires a documented rationale in `tests/hardhat/SKIPPED.md`):

- All `tests/hardhat/Fork/*.ts` — mainnet-fork tests, not portable to Endure's chain shape.
- `tests/hardhat/Admin/VBNBAdmin.ts` — IF BNB-specific assumptions cannot be neutralized for local network.
- Any other test that requires a real RPC endpoint or specific block height.

CI gating: `hardhat test` must exit 0. Skipped tests are listed in `SKIPPED.md` and the CI job verifies the skip list matches the actual `it.skip` invocations in the test files.

## Stance B audit update

The CI job `stance-b-audit` is repointed:

- Upstream repo: `VenusProtocol/venus-protocol`.
- Pinned commit: `6400a067114a101bd3bebfca2a4bd06480e84831`.
- Audit scope:
  - `packages/contracts/src/**/*.sol` excluding `src/endure/**` and `src/venus-staging/**` paths.
    - During the staging period, `src/venus-staging/**` is audited against `<venus>/contracts/**` with the staging prefix stripped.
    - Post Chunk 5b, `src/**/*.sol` (excluding `src/endure/`) is audited against `<venus>/contracts/**` directly.
  - `packages/contracts/src/test-helpers/venus/**/*.sol` is audited against `<venus>/contracts/test/**`.
  - Each `lib/@venusprotocol/<package>/` git submodule is audited against its pinned commit (recorded in `FORK_MANIFEST.md`).
- Audit failure modes (any of these fails CI):
  - A vendored file's SHA256 does not match upstream.
  - A vendored file's path does not exist upstream (orphan).
  - An upstream file path is missing from Endure's vendored tree (vendoring gap, but logged as warning, not failure, to allow tree-shake; FORK_MANIFEST.md records gaps explicitly).
  - A file under `src/endure/` references Moonwell-only types (forbidden-patterns scan).

## CI updates

CI workflow `.github/workflows/ci.yml` after Stage B:

- `contracts-build`: `forge build --root packages/contracts`.
- `contracts-test`: `forge test --root packages/contracts -v`.
- `contracts-hardhat-build`: `pnpm --filter @endure/contracts hardhat compile`.
- `contracts-hardhat-test`: `pnpm --filter @endure/contracts hardhat test`.
- `forbidden-patterns`: scans `src/` for stripped-feature identifiers (post-Stage-B target: Moonwell remnants like `MToken`, `MErc20`, `MErc20Delegator`, `mWell`, `WELL`, `xWELL` outside of `FORK_MANIFEST.md` or comments).
- `stance-b-audit`: as described in the Stance B audit section above.
- `e2e-smoke`: deploys Venus to local Anvil, runs the smoke script.
- `gas-snapshot-check`: Foundry-only, against the new Venus baseline.
- `pnpm-workspace`: SDK / frontend / keeper checks (unchanged).

CI runtime budget:
- Foundry jobs: similar to Phase 0 (~2 min).
- Hardhat jobs: NEW, expected ~5–10 min for the full upstream suite. Caching `hardhat-deploy` artifacts is required to keep this manageable.
- Stance B audit: NEW scope, expected ~30 sec for ~150 file SHA comparisons.

## Branch and PR strategy

- Long-lived branch: `phase-0.5-venus-rebase` (already exists, currently identical to main).
- Each chunk is one PR targeting `phase-0.5-venus-rebase`. PR title format: `phase 0.5: chunk N — <chunk title>`.
- Reviewers: at least one human reviewer per chunk PR. The Oracle agent may be consulted on Chunk 2 (deploy helper) and Chunk 5b (mass-move) for high-leverage review.
- Final integration: when all chunks land green, a single PR merges `phase-0.5-venus-rebase` into `main` with a squash merge. Pre-merge, tag `main` as `moonwell-v0.1.0` for archival/rollback.
- Rollback path: `git checkout moonwell-v0.1.0` returns to a fully working Phase 0 state. The squash-merge can be reverted as a single revert commit if a critical regression surfaces post-merge.

## Final-state success criteria

Phase 0.5 is complete when ALL of the following are true:

1. `forge build --root packages/contracts` exits 0.
2. `forge test --root packages/contracts` exits 0.
3. `pnpm --filter @endure/contracts hardhat compile` exits 0.
4. `pnpm --filter @endure/contracts hardhat test` exits 0.
5. Local Venus deployment script runs on Anvil with `--broadcast` and exits 0.
6. `scripts/e2e-smoke.sh` exercises mint / approve / supply / enterMarkets / borrow / repay / redeem against a live Anvil and exits 0.
7. Liquidation integration test proves LT is used for liquidation eligibility separately from CF.
8. A test proves direct vToken liquidation works while `liquidatorContract == address(0)`.
9. A test proves `setCollateralFactor` rejects LT < CF.
10. A test proves oracle price must be set before nonzero CF/LT.
11. A test proves `borrowCap == 0` disables borrowing (Venus semantic).
12. Solvency invariant passes at Phase 0 thresholds (1000 runs × 50 depth).
13. Stance B byte-identity audit passes against Venus pinned commit `6400a067` for every vendored file.
14. Forbidden-patterns scan passes (no Moonwell remnants in `src/` outside of comments / FORK_MANIFEST.md).
15. Behavior-mapping table covers every deleted Phase 0 test.
16. Gas snapshot passes against the new Venus baseline.
17. `FORK_MANIFEST.md`, `UPSTREAM.md`, `packages/contracts/README.md`, `skills/endure-architecture/SKILL.md` reflect Venus as the chassis.
18. `packages/contracts/src/venus-staging/` does NOT exist (final move complete).
19. `packages/contracts/src/Comptroller.sol`, `MToken.sol`, `MErc20*.sol` etc. (Moonwell files) do NOT exist.
20. `src/endure/MockResilientOracle.sol` exists; `src/endure/MockPriceOracle.sol` does NOT exist.
21. Branch `phase-0.5-venus-rebase` is squash-merged into `main`. Tag `moonwell-v0.1.0` exists pointing at the pre-merge `main`.

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Solc 0.5.16 + 0.8.25 mix breaks Hardhat compile | Medium | High | Configure both compilers in `hardhat.config.ts` from Chunk 1. Test compile early. Foundry tree-shakes 0.5.16 sources so they don't block forge build. |
| Diamond selector omission silently breaks runtime | Medium | High | Mandatory selector verification test in Chunk 2 (`DiamondSelectorRouting.t.sol`). CI gating. Use `Diamond(payable(unitroller)).facetAddress(selector)` to verify each selector explicitly. |
| Borrow cap semantic flip causes bugs in tests | High | Medium | Net-new test `BorrowCapSemantics.t.sol` in Chunk 3. Code review checklist item. Behavior-mapping rows for any cap-related Phase 0 test. |
| `setCollateralFactor` reverts silently if oracle unset | High | Medium | Deploy helper sequences: oracle prices set BEFORE CF/LT. Net-new test `CollateralFactorOrdering.t.sol`. |
| ComptrollerLens omission breaks liquidity calculations | Medium | High | Lens deployed and registered in Chunk 2's first commit. Test verifies `_setComptrollerLens` succeeded. |
| RewardFacet inheritance via PolicyFacet pulls in unwanted compile deps | Medium | Medium | Vendor full Venus tree (Decision #2) means all dependencies are present. Reward state is zero, so runtime impact is nil. |
| VAI/Prime/XVS test fixtures require BSC-specific assumptions | High | Medium | Each upstream test file is reviewed for BSC dependencies during Chunk 4. Tests with unfixable BSC deps go to `SKIPPED.md` with rationale. |
| Hardhat ↔ Foundry state divergence in deploy helpers | High | Medium | Endure's Anvil deployment (Foundry) and Hardhat test fixtures are explicitly state-isolated. No shared `addresses.json`. CI runs the two in parallel. |
| Mass-move commit (Chunk 5b) corrupts imports | Medium | High | Two-commit split: delete-Moonwell first (CI red expected), then mass-move + import-update. Each commit is mechanical and reviewable independently. Oracle review on Chunk 5b. |
| Stance B audit explodes in runtime due to large vendored tree | Low | Low | Audit script uses parallelized SHA256. Expected 30 sec for ~150 files. Cached upstream Venus checkout in CI. |
| Phase 0 Moonwell tests deleted without behavior-mapping row | Medium | High | CI script `check-test-mapping.sh` enforces 1:1 between deleted Phase 0 tests and mapping rows. Cannot merge Chunk 3 without it. |
| Endure-deployed surface accidentally drifts from upstream Venus | Low | High | Stance B byte-identity audit catches any drift in vendored files. Endure-authored files are forbidden-pattern-scanned for Moonwell type references. |
| Upstream Venus releases a breaking change before merge | Low | Medium | Pin is locked at `6400a067`. Future Venus updates are explicit decisions, not automatic. `UPSTREAM.md` documents the synchronization policy. |

## Out of scope

Reaffirmed from the original briefs, with one expansion:

- No Bittensor precompile integration.
- No real alpha custody.
- No real TAO native wrapper (WTAO is a plain ERC20 mock).
- No production oracle (MockResilientOracle is admin-set, not a real Resilient Oracle).
- No production governance (deployer EOA admin remains, Timelock/Governor deferred to Phase 4).
- No XVS, Prime, VAI as **product features**. The contracts are vendored byte-identical and deployed in Hardhat test fixtures only — they are upstream-validation evidence, not Endure features. Endure users cannot interact with VAI, Prime, or XVS through Endure's deployment.
- No external Liquidator deployed on Endure's Anvil. Direct vToken liquidation is the only liquidation path Endure exposes.
- No isolated pools (Venus Core Pool only).
- No flash loans (vendored, not deployed by Endure, not exposed to users).
- No production rewards (RewardFacet deployed with zero state purely to satisfy PolicyFacet inheritance).
- No frontend, SDK, or keeper changes except stale Moonwell naming/docs cleanup if necessary.

The expansion vs. the original briefs: VAI / Prime / XVS / Liquidator / Swap / DelegateBorrowers / VRT contracts ARE vendored and audited under Stance B even though they are not deployed as Endure features. This is a deliberate posture: maximum upstream-validation evidence, contracts are audit-clean and ready if Endure wants to enable them in a future phase.

## Implementation plan handoff

After this spec is approved, the next step is to invoke the writing-plans skill in a separate session to produce the updated `.sisyphus/plans/phase-0.5-venus-rebase.md`. The plan will encode the Task 0 + 6 chunks above as concrete checklists with test-first ordering, file paths, and acceptance criteria per task.

The spec stops at the level of "what" and "why." The plan covers "how" and "in what order."

## Resolved decisions log (formerly "Open decisions")

The previous spec listed five open decisions. All are resolved:

1. **Whether Stage A GREEN is sufficient to proceed immediately, or whether Stage B needs a separate implementation plan review.** Resolved: Stage A is currently YELLOW, not GREEN. Task 0 of this spec closes the YELLOW gates. Stage B begins only after Task 0 GREEN AND explicit team acceptance of this spec. The implementation plan in `.sisyphus/plans/` is regenerated by writing-plans skill after spec approval.
2. **Exact Stage B treatment for Moonwell v0.1.0: keep as tag only, branch it, or document rollback through the existing release.** Resolved: tag `moonwell-v0.1.0` is created on `main` immediately before the squash-merge of `phase-0.5-venus-rebase`. No long-lived Moonwell branch.
3. **Final Phase 0.5 CF/LT defaults for alpha markets.** Resolved: CF=0.25e18, LT=0.35e18. 10% gap for test visibility.
4. **Whether Stage B should include a no-op ProtocolShareReserve mock from the start or only after a tested runtime path requires it.** Resolved: lazy. Add only if a runtime path requires it; document in `FORK_MANIFEST.md` if added.
5. **Whether Stage B should include RewardFacet as dependency-only/no-op if PolicyFacet requires reward helper code.** Resolved: RewardFacet is deployed and registered in the diamondCut from day one. All reward speeds zero. Reward math is never modified.

End of spec.
