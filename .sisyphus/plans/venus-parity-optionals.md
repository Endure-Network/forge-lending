# Venus Parity + Optional Modules Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce Venus Core Pool Hardhat skips to only BSC/mainnet-specific tests, and add opt-in deployment/configuration surfaces so VAI, Prime, XVS rewards, and the external Liquidator can be used when deliberately enabled.

**Architecture:** Keep Endure Phase 0.5 default deployment unchanged: Core Pool only, mock local oracle/ACM, and no optional modules enabled by default. Add optional deployment/configuration entry points beside the existing local deploy paths, and align Hardhat tooling in an isolated first chunk so upstream Venus tests can be re-enabled safely. Treat BSC/mainnet-specific tests as permanent skips; treat toolchain-divergence skips as remediation targets.

**Tech Stack:** Solidity 0.8.25, Foundry, Hardhat, hardhat-deploy, ethers v5, smock, OpenZeppelin upgrades, pnpm workspace.

---

Canonical copy: `docs/superpowers/plans/2026-04-30-venus-parity-optionals.md`.

This `.sisyphus/plans/` copy exists so Momus can review the plan using the repository's plan-review workflow. Keep this file synchronized with the canonical copy before execution.

---

## Constraints and Non-Goals

- Do not modify vendored Venus Solidity under `packages/contracts/src/` except documented test-helper deviations if absolutely necessary.
- Do not enable VAI, Prime, XVS rewards, or Liquidator in the default `deployAll()` path.
- Do not make isolated pools part of this plan; isolated pools live in `venusprotocol/isolated-pools` and are outside Phase 0.5 Core Pool parity.
- Do not make production governance/oracle decisions here. Optional modules can use local/test mocks, but the scripts must make production dependencies explicit.
- Keep BSC/mainnet-specific tests permanently skipped unless a later product decision says to port BNB-specific behavior to Bittensor equivalents.
- Every chunk must preserve `forge build`, `forge test`, Hardhat compile, and the existing local smoke path.

---

## File Map

### Existing files to inspect or modify

- `packages/contracts/package.json` — Hardhat/smock/OZ/ethers dependency alignment.
- `package.json` / `pnpm-lock.yaml` — workspace dependency lock updates if package versions change.
- `packages/contracts/hardhat.config.ts` — test exclusion list, possible Venus `hardhat-deploy-ethers` alias setup, compiler/tooling config.
- `packages/contracts/tests/hardhat/SKIPPED.md` — authoritative skipped-test inventory.
- `scripts/check-hardhat-skips.sh` — drift gate between config and skip docs.
- `packages/contracts/FORK_MANIFEST.md` — durable record of accepted toolchain/deviation posture.
- `packages/contracts/src/endure/EndureDeployHelper.sol` — current Core Pool deploy helper; should stay default-only, with optional helpers added as separate APIs only if unavoidable.
- `packages/deploy/src/DeployLocal.s.sol` — current default Foundry deploy; should remain default-only.
- `packages/contracts/scripts/deploy-local.ts` — current default Hardhat deploy; should remain default-only.
- `packages/contracts/scripts/smoke-local.ts` — current default smoke; keep green.
- `packages/contracts/test/helper/BaseTest.t.sol` — likely base for optional module Foundry integration tests.
- `packages/contracts/test/endure/venus/RewardFacetEnable.t.sol` — existing XVS reward enablement test to extend or mirror.

### New files to create

- `packages/deploy/src/DeployWithOptionals.s.sol` — Foundry opt-in deployment script for optional modules.
- `packages/contracts/scripts/deploy-with-optionals.ts` — Hardhat opt-in deployment script for local frontend/integration use.
- `packages/contracts/scripts/configure-optionals.ts` — Hardhat post-deploy configuration helper.
- `packages/deploy/scripts/verify-optionals.sh` — Foundry/cast verification for optionals.
- `packages/contracts/test/endure/optionals/XVSRewards.t.sol` — Foundry integration coverage for XVS reward opt-in.
- `packages/contracts/test/endure/optionals/VAI.t.sol` — Foundry integration coverage for optional VAI.
- `packages/contracts/test/endure/optionals/Liquidator.t.sol` — Foundry integration coverage for optional external Liquidator.
- `packages/contracts/test/endure/optionals/Prime.t.sol` — Foundry integration coverage for Prime with explicit XVSVault dependency handling.
- `docs/optionals/DEPENDENCY-MAP.md` — dependency/order guide.
- `docs/optionals/XVS-REWARDS-GUIDE.md` — XVS rewards enablement guide.
- `docs/optionals/VAI-GUIDE.md` — VAI enablement guide.
- `docs/optionals/LIQUIDATOR-GUIDE.md` — Liquidator enablement guide.
- `docs/optionals/PRIME-GUIDE.md` — Prime enablement guide.

---

## Execution Chunks

For the detailed step-by-step implementation checklist, use the canonical plan at `docs/superpowers/plans/2026-04-30-venus-parity-optionals.md`. The chunks are:

1. Establish Hardhat parity baseline.
2. Align Hardhat toolchain against Venus.
3. Re-enable toolchain-divergence Hardhat tests by wave.
4. Make optional module deployment explicit.
5. Add Hardhat optional deployment and configuration surface.
6. Final verification and documentation cleanup.

---

## Acceptance Criteria

- `pnpm --filter @endure/contracts hardhat test` passes with only BSC/mainnet-specific permanent skips remaining.
- `scripts/check-hardhat-skips.sh` confirms skip docs and config match.
- Default `DeployLocal.s.sol`, `deploy-local.ts`, and smoke scripts remain unchanged in behavior.
- Optional deployment can enable XVS rewards, VAI, Liquidator, and Prime only when explicit env flags are provided.
- Optional deployment writes `addresses-optionals.json`, preserving the default `addresses.json` schema for existing consumers.
- Foundry tests under `test/endure/optionals/` pass.
- Stance B audit remains clean: no undocumented vendored Solidity divergence.
- Documentation explains dependency order and production caveats.

---

## Implementation Notes

- If a Hardhat parity fix requires modifying a vendored Venus test, stop and compare against upstream at `6400a067` first. Prefer dependency/tooling alignment over test edits.
- If a required optional-module setter is absent from Endure’s initial Diamond selector cut, write a failing selector-routing test before adding the selector.
- Prime is the riskiest optional module because it depends on XVS staking/XVSVault assumptions. Keep its deployment explicit and fail-fast unless dependencies are provided.
- Liquidator can be made useful before swap routing is complete by supporting direct repay-token liquidations first.
- VAI should not be exposed in default local deployment because it changes the risk surface and introduces mint-cap/rate/receiver configuration.
