# Venus Hardhat Parity Baseline

Date: 2026-04-30
Branch: `phase-0.5-venus-parity-optionals`

## Baseline gates

### Skip drift

Command:

```bash
bash scripts/check-hardhat-skips.sh
```

Result: exit 0.

Summary:

- `EXCLUDED_TEST_DIRS`: 1 entry (`Swap`)
- `EXCLUDED_TEST_FILES`: 9 entries
- `SKIPPED.md`: 9 file entries
- All config entries are documented and all documented entries are excluded.

### Current Hardhat suite

Command:

```bash
pnpm --filter @endure/contracts hardhat test
```

Result: exit 0, `463 passing (4m)`.

## Probe method

The current `TASK_TEST_GET_TEST_FILES` filter suppresses explicitly requested skipped files, so a direct targeted command against a skipped file reports `0 passing` while the exclusion is active. To capture real failure modes, I temporarily removed only the remediation-target exclusions (`W5`, `W6`, `W7`, `W11`, `W12`) from `packages/contracts/hardhat.config.ts`, ran each targeted probe, and restored the config before committing this evidence.

No production or test source files were changed during probing.

## Remediation candidate probes

### W5: `tests/hardhat/Liquidator/liquidatorTest.ts`

Command:

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/Liquidator/liquidatorTest.ts
```

Result: exit 9, `13 passing`, `1 pending`, `9 failing`.

Observed failures:

- smock duplicate-call assertions: `transfer`, `approve`, `liquidateBorrow`, `liquidateVAI`, and `VBNB.liquidateBorrow` were called twice where the upstream test expects exactly once or twice.
- Event amount assertions received `0` where expected treasury/liquidator split values were nonzero.
- Force VAI liquidation path reverted with `Insufficient allowance`.

This matches the documented W5 runtime-wrapper/smock-call-count category.

### W5: `tests/hardhat/Liquidator/liquidatorHarnessTest.ts`

Command:

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/Liquidator/liquidatorHarnessTest.ts
```

Result: exit 1, `3 passing`, `1 failing`.

Observed failure:

- `distributeLiquidationIncentive` expected `transfer` to be called exactly once, but smock observed it twice.

This matches the documented W5 smock duplicate-call category.

### W6: `tests/hardhat/Prime/Prime.ts`

Command:

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/Prime/Prime.ts
```

Result: exit 5, `0 passing`, `5 failing`.

Observed failure:

- Every fixture failed while deploying `PrimeScenario` through OpenZeppelin upgrades: `Contract src/test-helpers/venus/PrimeScenario.sol:PrimeScenario is not upgrade safe` because it is missing an initializer (`upgrades/error-001`).

This matches the documented W6 OpenZeppelin upgrades validation category.

### W7: `tests/hardhat/VAI/PegStability.ts`

Command:

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/VAI/PegStability.ts
```

Result: exit 36, `106 passing`, `36 failing`.

Observed failures:

- `swapVAIForStable` assertions saw duplicate smock calls for `transferFrom` / `burn`.
- `swapStableForVAI` with nonzero fees reverted with `AmountTooSmall()`.
- zero-fee `swapStableForVAI` paths minted `0` where the tests expected nonzero VAI amounts across 18-, 8-, and 6-decimal stable-token variants.

This partially matches the documented W7 zero-mint category and also exposes the same duplicate smock-call shape seen in W5/W11.

### W11: `tests/hardhat/DelegateBorrowers/SwapDebtDelegate.ts`

Command:

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/DelegateBorrowers/SwapDebtDelegate.ts
```

Result: exit 7, `5 passing`, `7 failing`.

Observed failures:

- smock duplicate-call assertions for `transferFrom`, `approve`, `repayBorrowBehalf`, `borrowBehalf`, `transfer`, and `sweepTokens`.
- Several second calls carried `0` amounts where exact-once upstream assertions expected only the nonzero call.

This matches the documented W11 smock duplicate-call category.

### W12: `tests/hardhat/integration/index.ts`

Command:

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/integration/index.ts
```

Result: exit 2, `0 passing`, `2 failing`.

Observed failure:

- smock failed to generate a fake from contract name `AccessControlManager` because no artifact with that exact name exists. Hardhat suggested `IAccessControlManagerV5` and `IAccessControlManagerV8`.

This matches the documented W12 artifact-resolution category.

## Permanent skip review

The Category A files remain permanent skips for BSC/mainnet specificity:

- `tests/hardhat/Swap/swapTest.ts`: depends on WBNB artifact and BSC liquidity-pool addresses.
- `tests/hardhat/XVS/XVSVaultFix.ts`: BSC mainnet fork test with hardcoded mainnet addresses.
- `tests/hardhat/DelegateBorrowers/MoveDebtDelegate.ts`: BNB-coupled flow plus incompatible OpenZeppelin upgrades behavior.

These should stay excluded unless a later product decision ports BNB/BSC-specific behavior to Bittensor equivalents.

## Upstream Venus tooling reference

The upstream Venus target (`VenusProtocol/venus-protocol@6400a067114a101bd3bebfca2a4bd06480e84831`) uses:

- `hardhat`: `2.22.18`
- `@defi-wonderland/smock`: `2.4.0`
- `@openzeppelin/hardhat-upgrades`: `^1.21.0`
- `ethers`: `^5.7.0`
- `hardhat-deploy`: `^0.12.4`
- `hardhat-deploy-ethers`: `^0.3.0-beta.13`
- `module-alias`: `^2.2.2`
- `_moduleAliases`: `@nomiclabs/hardhat-ethers` -> `node_modules/hardhat-deploy-ethers`
- `hardhat.config.ts` imports `module-alias/register` first, then imports `@nomiclabs/hardhat-ethers` through that alias.
- Venus also carries a `patch-package` patch for `@defi-wonderland/smock@2.4.0` to guard `provider.init()` for Hardhat 2.22.x lazy provider initialization.

## Conclusion

The current documented skip inventory is accurate. The full passing suite remains green with exclusions active, and the remediation-target probes reproduce the documented W5/W6/W7/W11/W12 categories. Chunk 2 should focus on the smallest proven Venus-compatible tooling alignment before removing any exclusions permanently.
