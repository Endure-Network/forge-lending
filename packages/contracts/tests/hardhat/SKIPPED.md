# Skipped Hardhat Tests

Tests excluded from `pnpm hardhat test` due to missing vendored infrastructure from Venus upstream.
All test files are byte-identical to Venus upstream (commit `6400a067`, tag `v10.2.0-dev.5`).
Exclusions are enforced via `TASK_TEST_GET_TEST_FILES` subtask override in `hardhat.config.ts`.

## Summary

| Status | Count |
|--------|-------|
| Passing | 15 (2 files) |
| Excluded | ~200+ tests (24 files) |

**Passing files:** `Unitroller/adminTest.ts` (10), `Utils/CheckpointView.ts` (5)

## Failure Categories

### A. Missing `helpers/utils.ts` (Venus TS helper not vendored)

Exports `convertToUnit()` and `convertToBigInt()` — Venus-specific test utilities.
Vendoring blocked by anti-creep rule (no new TypeScript helpers in Wave 4).

| Test file | Reason |
|-----------|--------|
| EvilXToken.ts | Imports `convertToUnit` from `helpers/utils` |
| Comptroller/Diamond/comptrollerTest.ts | Imports `convertToUnit` from `helpers/utils` |
| Comptroller/Diamond/flashLoan.ts | Imports `convertToUnit` from `helpers/utils` |
| Comptroller/Diamond/XVSSpeeds.ts | Imports `convertToUnit` from `helpers/utils` |
| Comptroller/Diamond/assetListTest.ts | Imports `convertToUnit` from `helpers/utils` |
| Comptroller/Diamond/repaymentMethod.ts | Imports `convertToUnit` from `helpers/utils` |
| Comptroller/Diamond/liquidateCalculateAmoutSeizeTest.ts | Imports `convertToUnit` from `helpers/utils` |
| Liquidator/liquidatorTest.ts | Imports `convertToBigInt`, `convertToUnit` from `helpers/utils` |
| Liquidator/liquidatorHarnessTest.ts | Imports `convertToBigInt`, `convertToUnit` from `helpers/utils` |
| Liquidator/restrictedLiquidations.ts | Imports `convertToBigInt` from `helpers/utils` |
| Lens/Rewards.ts | Imports `convertToUnit` from `helpers/utils` |
| VAI/PegStability.ts | Imports `convertToUnit` from `helpers/utils` |
| integration/index.ts | Imports `convertToUnit` from `helpers/utils` |

### B. Missing `helpers/deploymentConfig.ts` (Venus TS helper not vendored)

Exports `DEFAULT_BLOCKS_PER_YEAR` (BSC block rate constant = 10512000).

| Test file | Reason |
|-----------|--------|
| InterestRateModels/TwoKinksInterestRateModel.ts | Imports `DEFAULT_BLOCKS_PER_YEAR` |
| Prime/Prime.ts | Imports `DEFAULT_BLOCKS_PER_YEAR` + `convertToUnit` |
| Prime/PrimeLiquidityProvider.ts | Imports `DEFAULT_BLOCKS_PER_YEAR` + `convertToUnit` |
| XVS/XVSVault.ts | Imports `DEFAULT_BLOCKS_PER_YEAR` |
| fixtures/ComptrollerWithMarkets.ts | Imports `DEFAULT_BLOCKS_PER_YEAR` (used by VToken/reservesTest.ts) |

### C. Missing `script/deploy/comptroller/diamond` (Venus deploy utility not vendored)

Exports `FacetCutAction` enum and `getSelectors()` — Diamond Proxy pattern utilities.

| Test file | Reason |
|-----------|--------|
| Comptroller/Diamond/scripts/deploy.ts | Imports `FacetCutAction`, `getSelectors` |
| Comptroller/Diamond/diamond.ts | Imports `FacetCutAction`, `getSelectors` |

All Comptroller/Diamond tests depend on `scripts/deploy.ts`, so the entire suite is blocked.

### D. Missing Solidity test harness contracts (not vendored)

Venus upstream has test-only contracts in `contracts/test/` that were not included in the vendor scope.

| Test file | Missing artifact | Notes |
|-----------|-----------------|-------|
| Admin/VBNBAdmin.ts | `ComptrollerHarness` | Venus test harness contract |
| Unitroller/unitrollerTest.ts | `ComptrollerMock` | Venus test mock contract |
| VRT/VRTVault.ts | `AccessControlManager` | Only interfaces (V5/V8) are compiled |
| VAI/VAIController.ts | `BEP20Harness` | Venus test harness contract |
| DelegateBorrowers/SwapDebtDelegate.ts | `ComptrollerMock` | Venus test mock contract |

### E. Wrong fully-qualified artifact paths

Venus uses `paths.sources = "./contracts"`, Endure uses `paths.sources = "./src/venus-staging"`.
Artifact FQNs in tests reference `contracts/...` which doesn't match our compiled paths.

| Test file | Wrong path | Correct path would be |
|-----------|-----------|----------------------|
| VAI/VAIVault.ts | `contracts/Tokens/VAI/VAI.sol:VAI` | `src/venus-staging/Tokens/VAI/VAI.sol:VAI` |
| VToken/sweepTokenAndSyncCash.ts | `contracts/Comptroller/ComptrollerInterface.sol:ComptrollerInterface` | `src/venus-staging/Comptroller/ComptrollerInterface.sol:ComptrollerInterface` |

### F. BSC/BNB-specific

| Test file | Reason |
|-----------|--------|
| Swap/swapTest.ts | Requires `WBNB` contract artifact (BNB-specific, not applicable to Endure) |
| XVS/XVSVaultFix.ts | BSC mainnet fork test with hardcoded addresses + missing `XVSVaultProxy__factory` typechain |

### G. Missing plugins

| Test file | Reason |
|-----------|--------|
| DelegateBorrowers/MoveDebtDelegate.ts | Requires `@openzeppelin/hardhat-upgrades` (`upgrades.deployProxy` is undefined) |

## Resolution Path

To unblock these tests in a future task:
1. Vendor `helpers/utils.ts` and `helpers/deploymentConfig.ts` from Venus upstream → unblocks categories A + B (~18 files)
2. Vendor Solidity test harnesses (`ComptrollerMock`, `ComptrollerHarness`, `BEP20Harness`, `AccessControlManager`) → unblocks category D (~5 files)
3. Vendor `script/deploy/comptroller/diamond` → unblocks category C (Comptroller Diamond suite)
4. Fix FQN artifact paths in test files (or add `contracts/` → `src/venus-staging/` path aliasing) → unblocks category E
5. Install `@openzeppelin/hardhat-upgrades` → unblocks category G
6. BSC-specific tests (category F) remain permanently skipped
