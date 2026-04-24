# Endure Phase 0 Learnings

## [2026-04-24] Initial Setup

### Key Architecture Decisions
- Deployer EOA as admin on all 5 contracts (Unitroller + 3 MErc20Delegators + MockPriceOracle)
- NO custom multisig/governance contract in Phase 0
- All mock ERC20s use 18 decimals
- BORROW_CAP_ALPHA = 1 wei (NOT 0 — 0 means unlimited!)
- SEED_AMOUNT = 1e18 (1 whole token)

### Critical Ordering
- `mockOracle.setUnderlyingPrice(mToken, price)` MUST precede `_setCollateralFactor`
- Two-step Unitroller acceptance: `_setPendingImplementation` then `_become`
- After `_become`, use `Comptroller(address(unitroller))` as live comptroller

### Upstream Facts
- No `JumpRateModelV2` — actual file is `src/irm/JumpRateModel.sol`
- No `MGLMR.sol`/`MOVR.sol` — native markets use `MWethDelegate.sol`
- No git tags on moonwell-fi/moonwell-contracts-v2 — use main HEAD
- Upstream uses `evm_version = 'cancun'` — Endure overrides to `shanghai`

### Stance B (CRITICAL)
- ZERO modifications to any KEPT Moonwell .sol source file under packages/contracts/src/**
- Only allowed: delete files, modify test helpers (Task 13), modify foundry.toml/remappings.txt
- Any kept-core-file edit requires user approval + Fork Manifest entry

### EndureDeployHelper Design
- Abstract contract, NOT instantiated — consumers INHERIT
- `_deploy()` — broadcast-safe, NO vm.prank calls
- `_deployAs(roles)` — test-only, uses vm.startPrank(roles.admin)
- Lives in test/helper/ because it imports forge-std/Test.sol

## [2026-04-24] Tasks 12-13 config + cascade cleanup

### Cascades discovered after Stance B strip
- `ComptrollerStorage.sol` still imports `src/rewards/MultiRewardDistributor.sol`, so the rewards trio (`MultiRewardDistributor.sol`, `IMultiRewardDistributor.sol`, `MultiRewardDistributorCommon.sol`) must be restored from fork commit `518d4b1` even though broader reward/governance surfaces are being stripped.
- Removing `@proposals/` and xWELL/wormhole sources causes forge to fail on non-core scripts/tests that still import those paths; those files must be pruned or deleted to keep the Phase 0 build surface aligned with the stripped lending core.
- Deleting `src/4626/MoonwellERC4626.sol` also requires pruning remaining 4626 factory/deploy helpers that import it; otherwise forge build stops on `src/4626/Factory4626.sol` next.

- Task 12/13: after the strip, `ComptrollerStorage.sol` still required the MultiRewardDistributor type, so restoring `src/rewards/MultiRewardDistributor.sol`, `IMultiRewardDistributor.sol`, and `MultiRewardDistributorCommon.sol` from upstream commit `518d4b1` was necessary to keep core lending storage untouched.
- Task 12/13: helper pruning was already mostly complete; `BaseTest.t.sol` was reduced to a minimal `Test` base and the remaining Wormhole-only helper was `test/helper/BridgeOutHelper.sol`, which could be removed safely.

## [2026-04-24] Task 18 RBAC deployment helper

- `MErc20Delegator` admin must be passed explicitly from the intended admin role; using `msg.sender` inside a helper is unsafe because constructor/delegator admin expectations can diverge from the prank/original caller context.
- Guardian successor behavior is mixed upstream: `_setPauseGuardian` returns a non-zero error code on unauthorized access, while `_setBorrowCapGuardian` and `_setSupplyCapGuardian` revert.
- A dual-mode deployment helper works cleanly when `_deploy()` uses a synthesized all-equal `RoleSet` and `_deployAs()` wraps the entire deployment/setup sequence in one `vm.startPrank(roles.admin)` block.
