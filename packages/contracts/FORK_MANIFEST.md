# Endure Fork Manifest

This manifest tracks every divergence from upstream sources. The repository
is currently in a **dual-vendor intermediate state**: Phase 0 Moonwell v2
remains on the deployed surface while Phase 0.5 Venus Core Pool is staged
under `src/venus-staging/`. Stage B will fold Venus into `src/` and delete
the Moonwell tree.

- **Phase 0 (deployed)**: `moonwell-fi/moonwell-contracts-v2` @ `8d5fb1107babf7935cfabc2f6ecdb1722547f085`
- **Phase 0.5 staged (not deployed)**: `VenusProtocol/venus-protocol` @ `6400a067114a101bd3bebfca2a4bd06480e84831` (tag `v10.2.0-dev.5`)

Sections 1-5 below cover Phase 0 (Moonwell) audit trail. Section 6 covers
the Phase 0.5 (Venus) staging state.

## 1. Deleted Files (Strip Manifest)
- `src/governance/TemporalGovernor.sol` — cross-chain governance; Endure is single-chain
- `src/governance/ITemporalGovernor.sol`
- `src/governance/WormholeTrustedSender.sol`, `IWormholeTrustedSender.sol`
- `src/governance/multichain/*` — Wormhole-relayed governance
- `src/governance/Well.sol` — WELL governance token
- `src/wormhole/*` — Wormhole primitives
- `src/stkWell/*` — WELL staking safety module
- `src/IStakedWell.sol`
- `src/xWELL/*` — cross-chain WELL
- `src/rewards/MultiRewardsDeploy.sol` — deploy scaffolding for stripped rewards pipeline
- (NOTE: `MultiRewardDistributor.sol`, `IMultiRewardDistributor.sol`, and `MultiRewardDistributorCommon.sol` are intentionally KEPT, not stripped; `ComptrollerStorage.sol` imports them for storage layout. They remain byte-identical to upstream — see section 4.)
- `src/morpho/*` — Morpho integrations
- `src/tokensale/*` — WELL vesting
- `src/views/MorphoViews*.sol`, `MorphoBlueInterface.sol`, `MetaMorphoInterface.sol`
- `src/views/MoonwellViewsV2.sol`, `MoonwellViewsV3.sol`, `ProposalView.sol` — cascade deletions (imported stripped contracts)
- `src/4626/MoonwellERC4626.sol` — cascade deletion
- `src/oracles/ChainlinkOEVMorphoWrapper.sol` — cascade deletion (imported morpho)
- `proposals/mips/mip-b00/*`
- Test files for all of the above (see strip manifest in plan)
- Script files for all of the above

## 2. Modified Files (Stance B exceptions)
| File | Modified By Task | Change Scope | Rationale |
|------|------------------|--------------|-----------|
| `packages/contracts/test/helper/BaseTest.t.sol` | Task 13 | Import prunes + deletion of setup methods referencing stripped contracts | Test helper was tightly coupled to stripped governance |
| `packages/contracts/foundry.toml` | Task 12 | evm_version cancun→shanghai; optimizer_runs 1→200; remove RPC endpoints; add [invariant] profile | Endure-specific build target |
| `packages/contracts/remappings.txt` | Task 12 | Remove @wormhole/, @proposals/. Keep @forge-std/, @openzeppelin/, @protocol/, @test/, @utils/, @script/ | Wormhole stripped |

## 3. Added Files (Endure-authored)
| File | Added By Task | Purpose |
|------|---------------|---------|
| `src/endure/MockAlpha30.sol` | 15 | Phase 0 test alpha ERC20 (netuid 30) |
| `src/endure/MockAlpha64.sol` | 15 | Phase 0 test alpha ERC20 (netuid 64) |
| `src/endure/WTAO.sol` | 16 | Phase 0 mock Wrapped TAO |
| `src/endure/MockPriceOracle.sol` | 17 | Admin-set price oracle for Phase 0 |
| `src/endure/EndureRoles.sol` | 18 | Struct library bundling 4 role addresses (NOT a multisig) |
| `src/endure/EnduRateModelParams.sol` | 19 | Endure IRM + market param constants |
| `test/endure/**` | 15-24 | Endure test suites |
| `test/helper/EndureDeployHelper.sol` | 18 | Dual-mode (broadcast + test-only prank) deploy helper |
| `packages/deploy/src/DeployLocal.s.sol` | 20 | Phase 0 local Anvil deploy script |

## 4. Unchanged Files (Kept Core — ZERO diff vs upstream)
Every file under `packages/contracts/src/` NOT listed in sections 1-3 is byte-identical to upstream.

Explicit list:
- `Comptroller.sol`, `Unitroller.sol`, `ComptrollerStorage.sol`, `ComptrollerInterface.sol`
- `MToken.sol`, `MTokenInterfaces.sol`, `MErc20.sol`, `MErc20Delegate.sol`, `MErc20Delegator.sol`, `MLikeDelegate.sol`
- `MWethDelegate.sol`, `MWethOwnerWrapper.sol`, `WethUnwrapper.sol`
- `irm/JumpRateModel.sol`, `irm/InterestRateModel.sol`, `irm/WhitePaperInterestRateModel.sol`
- `oracles/ChainlinkOracle.sol`, `oracles/ChainlinkCompositeOracle.sol`, `oracles/PriceOracle.sol`, `oracles/AggregatorV3Interface.sol`, `oracles/StaticPriceFeed.sol`
- `Exponential.sol`, `ExponentialNoError.sol`, `SafeMath.sol`, `CarefulMath.sol`, `TokenErrorReporter.sol`
- `EIP20Interface.sol`, `EIP20NonStandardInterface.sol`
- `router/WETHRouter.sol`, `router/IWETH.sol`
- `Recovery.sol`, `OEVProtocolFeeRedeemer.sol`
- `4626/` (except deleted MoonwellERC4626.sol), `cypher/`, `market/`, `views/MoonwellViewsV1*.sol`
- `rewards/IMultiRewardDistributor.sol`, `rewards/MultiRewardDistributorCommon.sol` — kept byte-identical (required by `ComptrollerStorage.sol` storage layout)
- `rewards/MultiRewardDistributor.sol` — kept with documented import-path deviation; see section 5.1 below

## 5. Unresolved Deviations

### 5.1 `src/rewards/MultiRewardDistributor.sol` — five import paths rewritten

**Status**: Documented deviation (not byte-identical to upstream).

**Change**: Five import statements rewritten from `@protocol/*` to relative (`../*`) paths:

```diff
-import {MToken} from "@protocol/MToken.sol";
-import {Comptroller} from "@protocol/Comptroller.sol";
-import {MTokenInterface} from "@protocol/MTokenInterfaces.sol";
-import {ExponentialNoError} from "@protocol/ExponentialNoError.sol";
-import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
+import {MToken} from "../MToken.sol";
+import {Comptroller} from "../Comptroller.sol";
+import {MTokenInterface} from "../MTokenInterfaces.sol";
+import {ExponentialNoError} from "../ExponentialNoError.sol";
+import {MultiRewardDistributorCommon} from "./MultiRewardDistributorCommon.sol";
```

**Why**: The `packages/deploy/` forge package consumes the contracts source through
`allow_paths = ["../contracts"]` and its own remappings. When this file uses
`@protocol/*` imports (upstream style), Solidity resolves the same transitive
contracts (`MToken`, `MTokenInterfaces`, `ExponentialNoError`) through two
paths — once via `./rewards/...` from `ComptrollerStorage.sol` and once via
`@protocol/...` from this file — producing `Identifier already declared (2333)`
errors in the deploy package's compilation context.

The contracts package itself compiles cleanly with `@protocol/*` imports
(only one remapping active). The deploy package cannot, without deeper
remapping gymnastics that would break other `@protocol/*` consumers.

**Semantic equivalence**: The rewritten imports point to the same files via
different paths. No logic, types, or bytecode difference. `forge test` green
in both compilation contexts. We verified against upstream commit 8d5fb11 that
the remaining 1,244 lines of the file are byte-identical.

**Restoration path**: Any future refactor that unifies remapping resolution
across packages (e.g., a single top-level `remappings.txt` that both packages
consume via a shared `allow_paths`, or publishing contracts as a git
submodule) would let us restore byte-identical imports. Not pursued in
Phase 0 because the cost/benefit is wrong: we'd touch the build system to fix
a five-line cosmetic issue in a file we never deploy.

**Runtime impact**: None. `MultiRewardDistributor` is not deployed by
`DeployLocal.s.sol`. The file exists only because `ComptrollerStorage.sol`
imports it for storage layout, and `ComptrollerStorage` is kept as a Stance B
exception. Reward distribution is out of scope for Phase 0.

**Upstream backport policy**: If upstream Moonwell ships a security fix to
this file, re-apply the five import rewrites after backporting. The diff is
minimal and mechanical. Checked: `git show upstream/main -- src/rewards/MultiRewardDistributor.sol`.

## 6. Phase 0.5 Stage A — Venus Vendoring (Staged, Not Yet Deployed)

Stage A of the Phase 0.5 Venus rebase has been completed inside this
repository. Venus Core Pool is vendored byte-identical at commit
`6400a067114a101bd3bebfca2a4bd06480e84831` (tag `v10.2.0-dev.5`) under
`packages/contracts/src/venus-staging/`. Endure-authored Venus-shape mocks
and a tightened spike test prove all 8 hard gates from the spec.

Stage A is GREEN as of 2026-04-28. The team must explicitly accept this spec
before Stage B begins.

### 6.1 Venus tree vendored at `src/venus-staging/`

207 `.sol` files copied byte-identical from `<venus>/contracts/` at the
pinned commit. Stance B byte-identity audit posture: every file under
`src/venus-staging/` MUST hash-match the corresponding file at
`<venus>/contracts/<same-relative-path>`. Sample verification confirmed for
`src/venus-staging/Comptroller/Diamond/Diamond.sol` (SHA-256 match).

### 6.2 Three harness files NOT vendored (Stage A deviation)

The following Venus upstream files exist at `<venus>/contracts/test/` but
were NOT copied into `src/venus-staging/test/` because their relative
imports (`../../contracts/...`) only resolve under Hardhat, where the source
root is the Venus repo root, not the `contracts/` subtree:

- `contracts/test/VRTConverterHarness.sol`
- `contracts/test/VRTVaultHarness.sol`
- `contracts/test/XVSVestingHarness.sol`

All three are pragma `^0.5.16` legacy test infrastructure for VRT/XVS
Vesting — features that are out-of-Endure-scope. They will be re-vendored
in Stage B Chunk 4 when the Hardhat side-by-side toolchain lands and
relative-path resolution will work as upstream intends.

### 6.3 Venus external dependencies vendored at `lib/venusprotocol-*/`

131 `.sol` files across 5 packages, each byte-identical to the npm release
pinned by Venus's own package.json at the pinned commit:

| Package | Version | Source npm package |
|---------|---------|--------------------|
| `lib/venusprotocol-governance-contracts/` | `2.13.0` | `@venusprotocol/governance-contracts` |
| `lib/venusprotocol-oracle/` | `2.10.0` | `@venusprotocol/oracle` |
| `lib/venusprotocol-protocol-reserve/` | `3.4.0` | `@venusprotocol/protocol-reserve` |
| `lib/venusprotocol-solidity-utilities/` | `2.1.0` | `@venusprotocol/solidity-utilities` |
| `lib/venusprotocol-token-bridge/` | `2.7.0` | `@venusprotocol/token-bridge` |

Each directory has a `VENDOR.md` recording the package name, version, and
pinning evidence. Byte-identity is enforced for every `.sol` under each
package's `contracts/` subtree.

### 6.4 Endure-authored Venus-shape mocks (under `src/endure/`)

| File | Purpose |
|------|---------|
| `src/endure/MockResilientOracle.sol` | Implements Venus `ResilientOracleInterface`. Admin-set per-vToken prices via `setUnderlyingPrice`; admin-set per-asset prices via `setDirectPrice`; `updatePrice` and `updateAssetPrice` are no-ops. Replaces Phase 0's `MockPriceOracle.sol` for Stage B's deployed surface. |
| `src/endure/AllowAllAccessControlManager.sol` | Implements Venus `IAccessControlManagerV8` and OpenZeppelin `IAccessControl`. All bool-returning functions return `true`; all mutating functions are no-ops. Allows Venus contracts that gate calls behind ACM to pass through during Stage A spike testing without requiring a real governance deployment. |

Both mocks are explicitly documented as NOT FOR PRODUCTION USE.

### 6.5 Stage A spike test

`packages/contracts/test/endure/venus/VenusDirectLiquidationSpike.t.sol`
contains 7 tests that close all 8 spec hard gates:

1. `test_DiamondRegistersRequiredCoreSelectors` — Gate 3
2. `test_VBep20MarketsDeployAgainstUnitrollerProxy` — Gates 2, 5
3. `test_ResilientOracleMockSatisfiesPriceReads` — Gate 4
4. `test_FullLifecycleSupplyBorrowRepayRedeem` — Gate 6
5. `test_DirectVTokenLiquidationWorksWhenLiquidatorContractUnset` — Gate 7
6. `test_SetCollateralFactorRejectsLTBelowCF` — Gate 8
7. `test_DiamondRoutesLifecycleThroughUnitroller` — Gate 2 (lifecycle, beyond selectors)

Gate 1 (Foundry compile) is implicitly proven by the test file compiling.
59/59 tests pass (52 Phase 0 + 7 Stage A).

The spec called for `packages/contracts/test-foundry/` as the spike location.
Foundry's `test` config keys to a single directory, so the file lives under
`test/endure/venus/` (its Stage-B-final location per spec section "Test
porting strategy"). The spec's `test-foundry/` convention was tactical
scaffolding that turned out to be unnecessary.

### 6.6 Configuration deviations introduced by Stage A

- `foundry.toml` now uses `auto_detect_solc = true` (transitional;
  Stage B Chunk 5b reverts to pinned `solc_version = "0.8.25"` once
  Moonwell is removed). `evm_version` bumped from `shanghai` to `cancun`.
- `remappings.txt` adds `@openzeppelin/contracts-upgradeable/` and
  `@openzeppelin/contracts/` as more-specific entries than the existing
  `@openzeppelin/=lib/openzeppelin-contracts/`, so Solidity's
  longest-prefix-wins rule routes Moonwell's `@openzeppelin-contracts/...`
  imports and Venus's `@openzeppelin/contracts/...` imports correctly.
  Adds 5 `@venusprotocol/*` remappings.
- `packages/contracts/.gitignore` (new file) ignores Hardhat byproducts
  (`artifacts/`, `cache_hardhat/`, `deployments/localhost/`,
  `deployments/hardhat/`) in anticipation of Stage B Chunk 1.
