# Venus Parity + Optional Modules Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce Venus Core Pool Hardhat skips to only BSC/mainnet-specific tests, and add opt-in deployment/configuration surfaces so VAI, Prime, XVS rewards, and the external Liquidator can be used when deliberately enabled.

**Architecture:** Keep Endure Phase 0.5 default deployment unchanged: Core Pool only, mock local oracle/ACM, and no optional modules enabled by default. Add optional deployment/configuration entry points beside the existing local deploy paths, and align Hardhat tooling in an isolated first chunk so upstream Venus tests can be re-enabled safely. Treat BSC/mainnet-specific tests as permanent skips; treat toolchain-divergence skips as remediation targets.

**Tech Stack:** Solidity 0.8.25, Foundry, Hardhat, hardhat-deploy, ethers v5, smock, OpenZeppelin upgrades, pnpm workspace.

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

## Chunk 1: Establish Hardhat Parity Baseline

### Task 1: Capture the current skipped-test baseline

**Files:**
- Read: `packages/contracts/hardhat.config.ts`
- Read: `packages/contracts/tests/hardhat/SKIPPED.md`
- Read: `scripts/check-hardhat-skips.sh`
- Create: `.sisyphus/evidence/venus-parity-optionals/hardhat-baseline.md`

- [ ] **Step 1: Run current skip drift check**

Run:
```bash
bash scripts/check-hardhat-skips.sh
```

Expected: exit 0 with “no drift”.

- [ ] **Step 2: Run full current Hardhat suite**

Run:
```bash
pnpm --filter @endure/contracts hardhat test
```

Expected: 463 passing, 0 failing.

- [ ] **Step 3: Probe each skipped remediation candidate independently**

Run from repo root:
```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/Liquidator/liquidatorTest.ts
pnpm --filter @endure/contracts hardhat test tests/hardhat/Liquidator/liquidatorHarnessTest.ts
pnpm --filter @endure/contracts hardhat test tests/hardhat/Prime/Prime.ts
pnpm --filter @endure/contracts hardhat test tests/hardhat/VAI/PegStability.ts
pnpm --filter @endure/contracts hardhat test tests/hardhat/DelegateBorrowers/SwapDebtDelegate.ts
pnpm --filter @endure/contracts hardhat test tests/hardhat/integration/index.ts
```

Expected: failures matching `SKIPPED.md` categories W5, W6, W7, W11, W12. Record failure summaries in `.sisyphus/evidence/venus-parity-optionals/hardhat-baseline.md`.

- [ ] **Step 4: Verify permanent skips are truly environment-specific**

Review, do not necessarily run:
- `tests/hardhat/Swap/swapTest.ts`
- `tests/hardhat/XVS/XVSVaultFix.ts`
- `tests/hardhat/DelegateBorrowers/MoveDebtDelegate.ts`

Expected: direct BSC/mainnet/BNB assumptions. Record rationale in the evidence file.

- [ ] **Step 5: Commit baseline evidence**

```bash
git add .sisyphus/evidence/venus-parity-optionals/hardhat-baseline.md
git commit -m "test: capture venus hardhat parity baseline"
```

---

## Chunk 2: Align Hardhat Toolchain Against Venus

### Task 2: Test Venus-compatible Hardhat dependency alignment in isolation

**Files:**
- Modify: `packages/contracts/package.json`
- Modify: `pnpm-lock.yaml`
- Modify: `packages/contracts/hardhat.config.ts`

- [ ] **Step 1: Create a temporary worktree for dependency experimentation**

Run outside the main worktree if possible:
```bash
git worktree add ../forge-lending-hardhat-parity HEAD
```

Expected: isolated worktree exists. Perform dependency experiments there first.

- [ ] **Step 2: Add Venus-style ethers alias support**

Modify `packages/contracts/package.json` to include the Venus-compatible deploy ethers adapter if missing:
```json
"hardhat-deploy-ethers": "^0.3.0-beta.13",
"module-alias": "^2.2.3"
```

Modify `packages/contracts/hardhat.config.ts` near the imports:
```ts
import moduleAlias from "module-alias";

moduleAlias.addAlias("ethers", "hardhat-deploy-ethers");
```

If that alias breaks existing tests, replace it with the exact upstream Venus alias pattern from `VenusProtocol/venus-protocol` at commit `6400a067114a101bd3bebfca2a4bd06480e84831`.

- [ ] **Step 3: Pin upgrade/smock versions only as needed**

Try the smallest version movement first. If W5/W11 still fail, pin smock to the upstream-compatible version. If W6 still fails, align `@openzeppelin/hardhat-upgrades` with Venus’ expected version.

Expected package changes are likely one or more of:
```json
"@defi-wonderland/smock": "2.4.0",
"@openzeppelin/hardhat-upgrades": "^1.21.0"
```

Do not leave speculative version changes in the final branch. Keep only versions proven necessary by targeted tests.

- [ ] **Step 4: Install and compile**

Run:
```bash
pnpm install --frozen-lockfile=false
pnpm --filter @endure/contracts hardhat compile
```

Expected: compile exits 0.

- [ ] **Step 5: Run Foundry preservation gate**

Run:
```bash
forge build --root packages/contracts
forge test --root packages/contracts
```

Expected: both exit 0. If Foundry fails due to dependency/remapping side effects, revert the dependency experiment and try a narrower alias/version change.

- [ ] **Step 6: Commit minimal proven toolchain alignment**

```bash
git add packages/contracts/package.json pnpm-lock.yaml packages/contracts/hardhat.config.ts
git commit -m "test: align hardhat tooling with venus fixtures"
```

---

## Chunk 3: Re-enable Toolchain-Divergence Hardhat Tests by Wave

### Task 3: Re-enable W5 Liquidator tests

**Files:**
- Modify: `packages/contracts/hardhat.config.ts`
- Modify: `packages/contracts/tests/hardhat/SKIPPED.md`
- Test: `packages/contracts/tests/hardhat/Liquidator/liquidatorTest.ts`
- Test: `packages/contracts/tests/hardhat/Liquidator/liquidatorHarnessTest.ts`

- [ ] **Step 1: Remove only W5 files from `EXCLUDED_TEST_FILES`**

Delete:
```ts
"tests/hardhat/Liquidator/liquidatorHarnessTest.ts",
"tests/hardhat/Liquidator/liquidatorTest.ts",
```

- [ ] **Step 2: Run W5 tests**

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/Liquidator/liquidatorTest.ts
pnpm --filter @endure/contracts hardhat test tests/hardhat/Liquidator/liquidatorHarnessTest.ts
```

Expected: both pass. If they fail only on brittle exact smock call counts, inspect whether upstream Venus uses the same assertions. Prefer toolchain alignment over editing vendored tests.

- [ ] **Step 3: Update skip docs**

Remove W5 rows from `SKIPPED.md`, update summary counts, and explain that Liquidator parity is restored.

- [ ] **Step 4: Run full gates**

```bash
bash scripts/check-hardhat-skips.sh
pnpm --filter @endure/contracts hardhat test
forge build --root packages/contracts
forge test --root packages/contracts
```

Expected: all exit 0.

- [ ] **Step 5: Commit W5 restoration**

```bash
git add packages/contracts/hardhat.config.ts packages/contracts/tests/hardhat/SKIPPED.md
git commit -m "test: restore venus liquidator hardhat coverage"
```

### Task 4: Re-enable W6 Prime test

**Files:**
- Modify: `packages/contracts/hardhat.config.ts`
- Modify: `packages/contracts/tests/hardhat/SKIPPED.md`
- Test: `packages/contracts/tests/hardhat/Prime/Prime.ts`

- [ ] **Step 1: Remove Prime exclusion**

Delete:
```ts
"tests/hardhat/Prime/Prime.ts",
```

- [ ] **Step 2: Run Prime test**

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/Prime/Prime.ts
```

Expected: pass. If OZ validation still rejects `PrimeScenario`, first try the proven OZ version alignment from Chunk 2. Only if version alignment cannot work, add a documented test-helper-only patch to the fixture and record it in `FORK_MANIFEST.md`.

- [ ] **Step 3: Run full gates and commit**

```bash
bash scripts/check-hardhat-skips.sh
pnpm --filter @endure/contracts hardhat test
forge build --root packages/contracts
forge test --root packages/contracts
git add packages/contracts/hardhat.config.ts packages/contracts/tests/hardhat/SKIPPED.md packages/contracts/FORK_MANIFEST.md
git commit -m "test: restore venus prime hardhat coverage"
```

### Task 5: Re-enable W11 SwapDebtDelegate test

**Files:**
- Modify: `packages/contracts/hardhat.config.ts`
- Modify: `packages/contracts/tests/hardhat/SKIPPED.md`
- Test: `packages/contracts/tests/hardhat/DelegateBorrowers/SwapDebtDelegate.ts`

- [ ] **Step 1: Remove SwapDebtDelegate exclusion**

Delete:
```ts
"tests/hardhat/DelegateBorrowers/SwapDebtDelegate.ts",
```

- [ ] **Step 2: Run targeted test**

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/DelegateBorrowers/SwapDebtDelegate.ts
```

Expected: pass after hardhat-deploy-ethers/smock alignment. Do not loosen exact-once assertions unless upstream Venus at the pinned commit already differs.

- [ ] **Step 3: Run full gates and commit**

```bash
bash scripts/check-hardhat-skips.sh
pnpm --filter @endure/contracts hardhat test
forge build --root packages/contracts
forge test --root packages/contracts
git add packages/contracts/hardhat.config.ts packages/contracts/tests/hardhat/SKIPPED.md
git commit -m "test: restore venus swap debt delegate coverage"
```

### Task 6: Re-enable W12 integration test

**Files:**
- Modify: `packages/contracts/hardhat.config.ts`
- Modify: `packages/contracts/tests/hardhat/SKIPPED.md`
- Test: `packages/contracts/tests/hardhat/integration/index.ts`

- [ ] **Step 1: Remove integration exclusion**

Delete:
```ts
"tests/hardhat/integration/index.ts",
```

- [ ] **Step 2: Run integration test**

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/integration/index.ts
```

Expected: pass after smock/artifact resolution alignment. If `AccessControlManager` fake resolution fails, inspect TypeChain/artifact path expectations and add a local Hardhat artifact alias rather than editing production contracts.

- [ ] **Step 3: Run full gates and commit**

```bash
bash scripts/check-hardhat-skips.sh
pnpm --filter @endure/contracts hardhat test
forge build --root packages/contracts
forge test --root packages/contracts
git add packages/contracts/hardhat.config.ts packages/contracts/tests/hardhat/SKIPPED.md
git commit -m "test: restore venus integration hardhat coverage"
```

### Task 7: Re-enable W7 VAI PegStability test

**Files:**
- Modify: `packages/contracts/hardhat.config.ts`
- Modify: `packages/contracts/tests/hardhat/SKIPPED.md`
- Test: `packages/contracts/tests/hardhat/VAI/PegStability.ts`

- [ ] **Step 1: Remove PegStability exclusion**

Delete:
```ts
"tests/hardhat/VAI/PegStability.ts",
```

- [ ] **Step 2: Run targeted test**

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/VAI/PegStability.ts
```

Expected: pass. If zero-fee paths mint 0 VAI, inspect the failing fixture values and compare to upstream Venus at `6400a067`. Prefer fixing fixture/tooling configuration over changing vendored contract behavior.

- [ ] **Step 3: Run final Hardhat parity gates**

```bash
bash scripts/check-hardhat-skips.sh
pnpm --filter @endure/contracts hardhat test
forge build --root packages/contracts
forge test --root packages/contracts
bash scripts/check-stance-b.sh
```

Expected: all exit 0. Remaining skips should only be Category A BSC/mainnet-specific tests.

- [ ] **Step 4: Commit W7 restoration**

```bash
git add packages/contracts/hardhat.config.ts packages/contracts/tests/hardhat/SKIPPED.md
git commit -m "test: restore venus peg stability hardhat coverage"
```

---

## Chunk 4: Make Optional Module Deployment Explicit

### Task 8: Add Foundry optional deployment script skeleton

**Files:**
- Create: `packages/deploy/src/DeployWithOptionals.s.sol`
- Modify: `packages/deploy/README.md`
- Test: `packages/contracts/test/endure/optionals/XVSRewards.t.sol`

- [ ] **Step 1: Write failing XVS optional deployment test**

Create `packages/contracts/test/endure/optionals/XVSRewards.t.sol`:
```solidity
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import { BaseTest } from "../../helper/BaseTest.t.sol";
import { MockXVS } from "../../../src/endure/MockXVS.sol";
import { MarketFacet } from "../../../src/Comptroller/Diamond/facets/MarketFacet.sol";

contract XVSRewardsOptionalTest is BaseTest {
    function test_EnableXVSRewards_SetsSpeedsAndAllowsClaim() public {
        MockXVS xvs = new MockXVS();
        address[] memory markets = new address[](1);
        markets[0] = address(vWTAO);
        uint256[] memory supplySpeeds = new uint256[](1);
        uint256[] memory borrowSpeeds = new uint256[](1);
        supplySpeeds[0] = 1e18;
        borrowSpeeds[0] = 2e18;

        xvs.mint(address(this), 100e18);
        xvs.approve(address(helper), 100e18);
        helper.enableVenusRewards(address(xvs), markets, supplySpeeds, borrowSpeeds, 100e18);

        assertEq(MarketFacet(address(unitroller)).venusSupplySpeeds(address(vWTAO)), 1e18);
        assertEq(MarketFacet(address(unitroller)).venusBorrowSpeeds(address(vWTAO)), 2e18);
    }
}
```

- [ ] **Step 2: Run test and verify it passes or exposes current helper gap**

```bash
forge test --root packages/contracts --match-path test/endure/optionals/XVSRewards.t.sol -vvv
```

Expected: pass if existing `enableVenusRewards()` is sufficient. If it fails, minimally adjust only Endure-authored helper code.

- [ ] **Step 3: Add `DeployWithOptionals.s.sol` with XVS-only first path**

Create a script that:
1. Runs the existing `EndureDeployHelper.deployAll()`.
2. Deploys `MockXVS` for local optional reward testing.
3. Calls `enableVenusRewards()` with configurable zero/default speeds.
4. Writes an extended `addresses-optionals.json` without changing `addresses.json` default schema.

Use clear booleans/env flags:
```solidity
bool enableXVS = vm.envOr("ENABLE_XVS", false);
bool enableVAI = vm.envOr("ENABLE_VAI", false);
bool enableLiquidator = vm.envOr("ENABLE_LIQUIDATOR", false);
bool enablePrime = vm.envOr("ENABLE_PRIME", false);
```

- [ ] **Step 4: Run optional deploy with XVS only**

```bash
anvil --silent --disable-code-size-limit --gas-limit 1000000000 &
cd packages/deploy
ENABLE_XVS=true forge script src/DeployWithOptionals.s.sol \
  --rpc-url http://localhost:8545 --broadcast --slow --legacy --code-size-limit 999999
```

Expected: deployment exits 0 and writes `addresses-optionals.json` containing default core addresses plus `xvs`.

- [ ] **Step 5: Commit XVS optional foundation**

```bash
git add packages/deploy/src/DeployWithOptionals.s.sol packages/contracts/test/endure/optionals/XVSRewards.t.sol packages/deploy/README.md
git commit -m "feat: add optional xvs rewards deployment path"
```

### Task 9: Add optional VAI deployment and tests

**Files:**
- Modify: `packages/deploy/src/DeployWithOptionals.s.sol`
- Create: `packages/contracts/test/endure/optionals/VAI.t.sol`
- Modify: `docs/optionals/VAI-GUIDE.md`

- [ ] **Step 1: Write failing VAI integration test**

Create `VAI.t.sol` with tests for:
- VAI token and controller deployment.
- Mint requires sufficient collateral.
- Repay reduces VAI debt.
- Mint cap is enforced.

Keep test setup local; do not enable VAI in `deployAll()`.

- [ ] **Step 2: Run failing test**

```bash
forge test --root packages/contracts --match-path test/endure/optionals/VAI.t.sol -vvv
```

Expected: fail until optional deployment helper exists.

- [ ] **Step 3: Implement VAI optional deployment in `DeployWithOptionals.s.sol`**

Deploy:
- `VAI`
- `VAIUnitroller`
- `VAIController`

Wire:
- pending implementation / become flow
- Comptroller VAI controller reference if required by available SetterFacet selectors
- base rate, float rate, mint cap, receiver/treasury values from env defaults

If the current Endure diamond selector cut does not expose a required VAI setter, add the selector in `EndureDeployHelper` only with a failing selector-routing test first.

- [ ] **Step 4: Run VAI tests and deploy script**

```bash
forge test --root packages/contracts --match-path test/endure/optionals/VAI.t.sol
ENABLE_VAI=true forge script src/DeployWithOptionals.s.sol \
  --rpc-url http://localhost:8545 --broadcast --slow --legacy --code-size-limit 999999
```

Expected: both pass.

- [ ] **Step 5: Commit VAI optional path**

```bash
git add packages/deploy/src/DeployWithOptionals.s.sol packages/contracts/test/endure/optionals/VAI.t.sol docs/optionals/VAI-GUIDE.md
git commit -m "feat: add optional vai deployment path"
```

### Task 10: Add optional Liquidator deployment and tests

**Files:**
- Modify: `packages/deploy/src/DeployWithOptionals.s.sol`
- Create: `packages/contracts/test/endure/optionals/Liquidator.t.sol`
- Create: `docs/optionals/LIQUIDATOR-GUIDE.md`

- [ ] **Step 1: Write failing Liquidator integration test**

Test:
- Liquidator can be deployed with Comptroller/VAIController dependencies.
- Liquidator can liquidate a vToken borrow and seize collateral.
- Restricted liquidation allowlist works.
- VAI liquidation path is skipped unless `ENABLE_VAI=true` setup is present.

- [ ] **Step 2: Run failing test**

```bash
forge test --root packages/contracts --match-path test/endure/optionals/Liquidator.t.sol -vvv
```

Expected: fail until optional deployment is implemented.

- [ ] **Step 3: Implement Liquidator optional deployment**

Deploy `Liquidator` with explicit env/defaults for:
- Comptroller address
- AccessControlManager address
- ProtocolShareReserve address or local test stub
- treasury percent
- min liquidatable VAI

Do not require SwapRouter for first pass; document swap-backed liquidation as later expansion.

- [ ] **Step 4: Run tests and deploy script**

```bash
forge test --root packages/contracts --match-path test/endure/optionals/Liquidator.t.sol
ENABLE_VAI=true ENABLE_LIQUIDATOR=true forge script src/DeployWithOptionals.s.sol \
  --rpc-url http://localhost:8545 --broadcast --slow --legacy --code-size-limit 999999
```

Expected: pass.

- [ ] **Step 5: Commit Liquidator optional path**

```bash
git add packages/deploy/src/DeployWithOptionals.s.sol packages/contracts/test/endure/optionals/Liquidator.t.sol docs/optionals/LIQUIDATOR-GUIDE.md
git commit -m "feat: add optional liquidator deployment path"
```

### Task 11: Add optional Prime deployment with explicit XVSVault dependency

**Files:**
- Modify: `packages/deploy/src/DeployWithOptionals.s.sol`
- Create: `packages/contracts/test/endure/optionals/Prime.t.sol`
- Create: `docs/optionals/PRIME-GUIDE.md`

- [ ] **Step 1: Write failing Prime dependency test**

Test that Prime optional deployment refuses to run without an explicit XVSVault-compatible address or local test stub.

- [ ] **Step 2: Write Prime happy-path test with a local test XVSVault-compatible stub**

Create the minimum test-only XVSVault-compatible stub under `packages/contracts/test/endure/optionals/` if needed. Do not add a production XVSVault replacement.

- [ ] **Step 3: Implement Prime optional deployment**

Deploy:
- `PrimeLiquidityProvider`
- `Prime`

Configure:
- XVS token
- XVSVault address from `XVS_VAULT` env or test stub
- Comptroller
- markets and multipliers from local defaults

Expected behavior: `ENABLE_PRIME=true` fails early with a clear message unless `ENABLE_XVS=true` and `XVS_VAULT` or local test mode is provided.

- [ ] **Step 4: Run tests and deploy script**

```bash
forge test --root packages/contracts --match-path test/endure/optionals/Prime.t.sol
ENABLE_XVS=true ENABLE_PRIME=true XVS_VAULT=<address> forge script src/DeployWithOptionals.s.sol \
  --rpc-url http://localhost:8545 --broadcast --slow --legacy --code-size-limit 999999
```

Expected: pass with explicit dependency.

- [ ] **Step 5: Commit Prime optional path**

```bash
git add packages/deploy/src/DeployWithOptionals.s.sol packages/contracts/test/endure/optionals/Prime.t.sol docs/optionals/PRIME-GUIDE.md
git commit -m "feat: add optional prime deployment path"
```

---

## Chunk 5: Add Hardhat Optional Deployment and Configuration Surface

### Task 12: Add Hardhat opt-in deploy script

**Files:**
- Create: `packages/contracts/scripts/deploy-with-optionals.ts`
- Modify: `packages/contracts/README.md`

- [ ] **Step 1: Implement script structure**

The script should:
1. Require `chainId === 31337`.
2. Run the same core deployment path as `deploy-local.ts` or consume existing `addresses.json` when `REUSE_CORE=true`.
3. Respect env flags `ENABLE_XVS`, `ENABLE_VAI`, `ENABLE_LIQUIDATOR`, `ENABLE_PRIME`.
4. Write `packages/deploy/addresses-optionals.json`.
5. Never overwrite the default 16-key `addresses.json` unless explicitly requested.

- [ ] **Step 2: Run Hardhat deploy with XVS only**

```bash
pnpm --filter @endure/contracts hardhat node
ENABLE_XVS=true pnpm --filter @endure/contracts hardhat run scripts/deploy-with-optionals.ts --network localhost
```

Expected: exits 0 and writes `addresses-optionals.json`.

- [ ] **Step 3: Run with VAI + Liquidator after Foundry path is green**

```bash
ENABLE_XVS=true ENABLE_VAI=true ENABLE_LIQUIDATOR=true pnpm --filter @endure/contracts hardhat run scripts/deploy-with-optionals.ts --network localhost
```

Expected: exits 0.

- [ ] **Step 4: Commit Hardhat optional deploy**

```bash
git add packages/contracts/scripts/deploy-with-optionals.ts packages/contracts/README.md
git commit -m "feat: add hardhat optional module deploy script"
```

### Task 13: Add Hardhat configuration helper

**Files:**
- Create: `packages/contracts/scripts/configure-optionals.ts`
- Create: `docs/optionals/DEPENDENCY-MAP.md`
- Create: `docs/optionals/XVS-REWARDS-GUIDE.md`

- [ ] **Step 1: Implement config subcommands or env-driven actions**

Support actions:
- `configure-xvs-rewards`
- `configure-vai`
- `configure-liquidator`
- `configure-prime`

Prefer an env var `OPTIONAL_ACTION` over adding a CLI parser dependency.

- [ ] **Step 2: Validate config script on local node**

```bash
OPTIONAL_ACTION=configure-xvs-rewards pnpm --filter @endure/contracts hardhat run scripts/configure-optionals.ts --network localhost
```

Expected: reward speeds update or a clear validation error if required addresses are missing.

- [ ] **Step 3: Commit config helper and docs**

```bash
git add packages/contracts/scripts/configure-optionals.ts docs/optionals/DEPENDENCY-MAP.md docs/optionals/XVS-REWARDS-GUIDE.md
git commit -m "docs: document optional venus module configuration"
```

---

## Chunk 6: Final Verification and Documentation Cleanup

### Task 14: Add optional verification script

**Files:**
- Create: `packages/deploy/scripts/verify-optionals.sh`
- Modify: `scripts/README.md`

- [ ] **Step 1: Implement cast-based verification**

The script should:
- read `packages/deploy/addresses-optionals.json`
- verify nonzero optional addresses for enabled modules
- call simple read methods:
  - XVS: `totalSupply()`
  - Comptroller: `getXVSAddress()` / `venusSupplySpeeds(address)`
  - VAI: `totalSupply()` and controller VAI address
  - Liquidator: `treasuryPercentMantissa()`
  - Prime: `isUserPrimeHolder(address)` or equivalent safe read

- [ ] **Step 2: Run full optional deploy + verify**

```bash
anvil --silent --disable-code-size-limit --gas-limit 1000000000 &
cd packages/deploy
ENABLE_XVS=true ENABLE_VAI=true ENABLE_LIQUIDATOR=true forge script src/DeployWithOptionals.s.sol \
  --rpc-url http://localhost:8545 --broadcast --slow --legacy --code-size-limit 999999
bash scripts/verify-optionals.sh
```

Expected: verify script exits 0.

- [ ] **Step 3: Commit verification script**

```bash
git add packages/deploy/scripts/verify-optionals.sh scripts/README.md
git commit -m "test: add optional module deployment verifier"
```

### Task 15: Final all-gates run

**Files:**
- Modify: `packages/contracts/tests/hardhat/SKIPPED.md`
- Modify: `packages/contracts/FORK_MANIFEST.md`
- Modify: `packages/contracts/README.md`
- Modify: `packages/deploy/README.md`

- [ ] **Step 1: Run default gates**

```bash
forge build --root packages/contracts
forge test --root packages/contracts
pnpm --filter @endure/contracts hardhat compile
pnpm --filter @endure/contracts hardhat test
bash scripts/check-stance-b.sh
bash scripts/check-forbidden-patterns.sh
bash scripts/check-test-mapping.sh
bash scripts/check-hardhat-skips.sh
bash scripts/gas-snapshot-check.sh
```

Expected: all exit 0.

- [ ] **Step 2: Run default live deploy smoke**

```bash
anvil --silent --disable-code-size-limit --gas-limit 1000000000 &
cd packages/deploy
forge script src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast --slow --legacy --code-size-limit 999999
cd ../..
bash scripts/e2e-smoke.sh
```

Expected: default smoke exits 0. This proves optionals did not alter default behavior.

- [ ] **Step 3: Run optional live deploy smoke**

```bash
anvil --silent --disable-code-size-limit --gas-limit 1000000000 &
cd packages/deploy
ENABLE_XVS=true ENABLE_VAI=true ENABLE_LIQUIDATOR=true forge script src/DeployWithOptionals.s.sol \
  --rpc-url http://localhost:8545 --broadcast --slow --legacy --code-size-limit 999999
bash scripts/verify-optionals.sh
```

Expected: optional verify exits 0.

- [ ] **Step 4: Commit final docs cleanup**

```bash
git add packages/contracts/tests/hardhat/SKIPPED.md packages/contracts/FORK_MANIFEST.md packages/contracts/README.md packages/deploy/README.md docs/optionals
git commit -m "docs: finalize venus parity and optional modules guidance"
```

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
