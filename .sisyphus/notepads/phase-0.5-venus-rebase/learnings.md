# Learnings — Phase 0.5 Venus Rebase

## PATH CONVENTIONS (CRITICAL)
- Bare `src/`, `test/`, `lib/`, `foundry.toml`, `remappings.txt`, `hardhat.config.ts` etc. = relative to `packages/contracts/`
- `packages/`, `scripts/`, `docs/`, `.github/`, `.sisyphus/`, `README.md`, `skills/` = repo root
- Full path `packages/contracts/src/venus-staging/...` to avoid confusion
- `packages/deploy/src/DeployLocal.s.sol` is the deploy-script package, NOT contracts

## STAGE A STATE (VERIFIED AT PLANNING TIME)
- `src/venus-staging/` populated at commit `6400a067`
- `src/endure/MockResilientOracle.sol` exists (79 LOC) — DO NOT re-author
- `src/endure/AllowAllAccessControlManager.sol` exists (78 LOC) — DO NOT re-author
- `lib/venusprotocol-*` 5 packages vendored
- `test/endure/venus/VenusDirectLiquidationSpike.t.sol` — 7 passing tests, 61 spike selectors
- `foundry.toml`: `auto_detect_solc = true`, `evm_version = "cancun"`, optimizer 200 runs
- Spike `setUp` has `_deployMocks` → `_deployDiamondAndFacets` → `_wireDiamondPolicy` → `_deployMarkets` → `_supportAndConfigureMarkets` → `_seedSupply` pattern

## SELECTOR EXPANSION (T8/T9 KEY FACTS)
- Spike had 61 selectors; plan expands to 71 (+10)
- MarketFacet: 31→33 (+2: `venusSupplySpeeds(address)` + `venusBorrowSpeeds(address)`)
- PolicyFacet: 16→17 (+1: `_setVenusSpeeds(VToken[],uint256[],uint256[])` at PolicyFacet.sol:477)
- SetterFacet: 12→13 (+1: `_setXVSToken(address)` at SetterFacet.sol:604)
- RewardFacet: 2→8 (+6 new selectors)

## VENUS vs MOONWELL SEMANTIC DIFFERENCES
- `setCollateralFactor` (Venus) has NO leading underscore (Moonwell has `_setCollateralFactor`)
- `setLiquidationIncentive` is PER-MARKET in Venus (not global)
- Borrow cap 0 = DISABLED in Venus (Moonwell: unlimited)
- `setIsBorrowAllowed(uint96 poolId, address vToken, bool)` needed to enable borrowing on vWTAO
- `markets()` returns 7-tuple (not 3-tuple); finding F4

## DEPLOY ORDER (ORDERING CONSTRAINTS)
1. ACM → Oracle → Lens → Unitroller → Diamond → Facets
2. diamondCut (71 selectors)
3. _setComptrollerLens → _setPriceOracle → _setAccessControl
4. Deploy underlyings → Deploy IRMs → Deploy VBep20Immutable markets
5. supportMarket for each
6. SET ORACLE PRICES (BEFORE CF/LT)
7. setCollateralFactor / setLiquidationIncentive (after oracle prices)
8. Seed-and-burn each market

## IRM PARAMS (Venus TwoKinks = 8 int256 params)
- WTAO: baseRate=0.02e18, multiplier=0.10e18, kink1=0.50e18, multiplier2=0.50e18, baseRate2=0, kink2=0.80e18, jump=3e18, blocksPerYear=2628000
- Alpha: all zeros except kink1=0.99e18, kink2=1e18 (constructor requires kink2 > kink1 > 0)

## DUAL-HELPER STRATEGY
- `EndureDeployHelper.sol` (Phase 0 Moonwell) stays UNTOUCHED until T46b
- `EndureDeployHelperVenus.sol` (NEW) serves Venus tests through T46b
- T46b: delete Moonwell helper, rename Venus helper → EndureDeployHelper.sol

## T1 VERIFICATION — Stage A Artifacts (2026-04-28)
- Branch: `phase-0.5-venus-rebase` (up to date with origin)
- .upstream-sha: `8d5fb1107babf7935cfabc2f6ecdb1722547f085`
- All 4 Stage A source/test files: PRESENT
- All 5 lib/venusprotocol-* packages: PRESENT
- foundry.toml: auto_detect_solc=true, evm_version=cancun — CONFIRMED
- remappings.txt: 5 @venusprotocol/ entries — CONFIRMED
- forge build: PASS (no files changed, compilation skipped — already compiled)
- forge test: PASS — 59 tests passed, 0 failed (14 suites)
- VenusDirectLiquidationSpike.t.sol: 7/7 passed
- git status: clean for contract/source files; only .sisyphus/ and docs/briefs/ untracked/modified (expected)
- scripts/check-stance-b.sh: NOT YET CREATED (pre-T40) — Stance B audit DEFERRED
- Evidence files: .sisyphus/evidence/task-1-forge-build.log, task-1-forge-test.log, task-1-git-status.log, task-1-stance-b-audit.log

## [2026-04-29] Task: T2
- Hardhat config created with dual compiler: 0.5.16 + 0.8.25 + cancun + hardhat-deploy
- pnpm install succeeded; `pnpm --filter @endure/contracts hardhat --version` works (2.28.6)
- Added `"hardhat": "hardhat"` script to package.json to enable `pnpm --filter @endure/contracts hardhat --version`
- Foundry unaffected (build + 59 tests still pass)
- .gitignore already had artifacts/, cache_hardhat/, deployments/localhost/, deployments/hardhat/ — added typechain-types/

## [2026-04-29] Tasks: T3, T4, T5
- Venus tests/hardhat/ vendored from 6400a067 (37 non-fork .ts files; Fork/ excluded)
- Venus deploy/ vendored (25 .ts scripts)
- git mv src/venus-staging/test → src/test-helpers/venus (47 .sol files; byte-identity preserved)
- forge build + 59 tests still green after move
- NOTE: T5 is a MOVE, not a fresh copy - git history preserved via git mv
- GOTCHA: Moved test helpers had relative imports `../` pointing to venus-staging/. After move to src/test-helpers/venus/, needed to update all `../` to `../../venus-staging/` in 27 files (used sed in-place)
- GOTCHA: VenusDirectLiquidationSpike.t.sol imported MockToken via @protocol/venus-staging/test/MockToken.sol — updated to @protocol/test-helpers/venus/MockToken.sol
- Commit: 68e2fe2 "chore(contracts): vendor venus hardhat tests + deploy + move test helpers to steady-state path"

## [2026-04-29] Task: T6
- contracts-hardhat-build CI job added; runs parallel to contracts-build (no needs: dependency)
- Node 22 + pnpm 10.28.1 (matches pnpm-workspace job pattern; used @v6 actions to match existing)
- pnpm --filter @endure/contracts hardhat compile exits 0 locally ("Nothing to compile" — artifacts already up to date)
- forge build --root packages/contracts exits 0 (no regressions)

## [2026-04-29] Tasks: T7, T8
- Deploy.t.sol: TDD RED - imports EndureDeployHelperVenus which doesn't exist yet
- DiamondSelectorRouting.t.sol: 71 selectors verified (33+17+13+8)
- Spike's selector lists copied verbatim as baseline, then expanded
- Both tests fail with compile error (expected TDD RED state) — exit code 1
- markets() tuple: 7 fields (bool isListed, uint256 cf, bool isVenus, uint256 lt, uint256 li, uint96 poolId, bool isBorrowAllowed)
- Diamond.facetAddress(bytes4) returns FacetAddressAndPosition struct — must use .facetAddress field
- Existing 59 tests pass on clean baseline (before new files); new files cause compile failure when included
- Note: forge compiles all test files together; --no-match-path doesn't prevent compilation of excluded files
- Commit: 46eed49 "test(endure): add deploy + diamond selector failing tests"

## [2026-04-29] Task: T9
- EndureDeployHelperVenus.sol created with 71-selector diamondCut
- Deployment sequence: ACM → Oracle → Lens → Unitroller → Diamond → facets → _become → diamondCut
- _become() called by Diamond impl with unitroller address: diamond._become(unitroller)
- Unitroller._setPendingImplementation must be called BEFORE diamond._become
- DiamondSelectorRouting.t.sol GREEN (all 71 selectors routing correctly)
- Deploy.t.sol partial GREEN (infrastructure addresses non-zero, markets still zero — T10 handles)
- Old EndureDeployHelper.sol untouched — 59 Moonwell + 7 spike tests still green

## [2026-04-29] Task: T10
- EndureDeployHelperVenus Phase 2: wire ACM/oracle/lens + deploy underlyings/IRMs/vTokens/supportMarket/setOraclePrices
- TwoKinksInterestRateModel: 8 int256 params — alpha kink1=0.99e18, kink2=1e18 to satisfy kink2>kink1>0 invariant
- VBep20Immutable constructor arg order: (underlying, comptroller, irm, initialExchangeRate, name, symbol, decimals, admin)
- oracle prices MUST be set BEFORE calling CF/LT setters (T11 ordering constraint)
- Setter methods accessed via Diamond proxy: SetterFacet(address(unitroller))._setComptrollerLens(...)
- EnduRateModelParams kept Moonwell-compatible while adding Venus-specific int256 TwoKinks constants in the same file

## [2026-04-29] Task: T11
- Phase 3: setCF/LT (NO leading underscore) AFTER oracle prices — setCollateralFactor returns uint error code
- setLiquidationIncentive: PER-MARKET, NO leading underscore, per-market call
- _setCloseFactor: HAS leading underscore; global
- setIsBorrowAllowed(0, address(vWTAO), true): enables vWTAO borrowing (poolId=0 = core pool)
- borrow cap 0 in Venus = DISABLED (alpha markets set to 0 = disabled)
- seed-and-burn: mint underlying → approve vToken → vToken.mint → vToken.transfer(0xdEaD, received)
- enableVenusRewards(): SEPARATE function from deployAll(); caller must approve helper first
- Store deployedUnitroller as state var for enableVenusRewards to use post-deploy

## [2026-04-29] Task: T12
- DeployLocal.s.sol rewritten to call EndureDeployHelperVenus.deployAll()
- addresses.json: 16 keys (unitroller, comptrollerLens, accessControlManager, resilientOracle, 4 facets, 3 vTokens, 2 IRMs, 3 underlyings)
- foundry.toml: updated solc_version → auto_detect_solc=true, evm_version=cancun, code_size_limit=999999, fs_permissions expanded
- remappings.txt: added @openzeppelin/contracts/, @venusprotocol/* remappings pointing to ../contracts/lib/
- CRITICAL: EndureDeployHelperVenus is 124KB (5x EIP-170 limit). Anvil MUST be started with --disable-code-size-limit and --gas-limit 999999999
- forge script must use --code-size-limit 999999 flag
- vm.envOr used for PRIVATE_KEY with anvil default key as fallback
- Anvil deploy succeeded; cast call verified comptrollerLens non-zero (0xeEBe00Ac0756308ac4AaBfD76c05c4F3088B8883)

## [2026-04-29] Task: T13
- Behavior mapping table created at docs/briefs/phase-0.5-venus-rebase-test-mapping.md
- check-test-mapping.sh: checks 9 Phase 0 test paths; exits 1 if any deleted without mapping row
- CI: contracts-test job now runs mapping check before forge test
- Script strategy: hardcoded list of Phase 0 test paths; checks if file is missing AND if mapping row exists
- Verified: no deletions → exit 0; deletion with mapping row → exit 0; deletion without mapping row → exit 1

## [2026-04-29] Tasks: T14-T23 (Wave 3)
- AliceLifecycle, Liquidation, SeedDeposit, RBACSeparation, IRM params, MockAlpha, WTAO: ported to Venus
- DenyAllAccessControlManager.sol created for negative-path ACM tests
- LiquidationThreshold, CollateralFactorOrdering, BorrowCapSemantics: net-new tests
- RewardFacetEnable + MockXVS: proves reward enable path end-to-end
- VenusDirectLiquidationSpike.t.sol renamed to Lifecycle.t.sol
- All tests pass; behavior-mapping table updated
- Key Venus-vs-Compound difference: borrowCap=0 DISABLES borrowing (require(borrowCap != 0)); Compound treats cap=0 as unlimited
- MockResilientOracle admin is the deployer (helper); tests transfer admin via setAdmin() for price manipulation
- Venus isBorrowAllowed check comes before borrowCap check in PolicyFacet.borrowAllowed
- DenyAll ACM causes Venus to revert("access denied") on setMarketBorrowCaps
- 68 tests passing, 0 failing after Wave 3 completion
