# Endure Fork Manifest

Audit trail of every divergence from `moonwell-fi/moonwell-contracts-v2` at pinned commit `8d5fb1107babf7935cfabc2f6ecdb1722547f085`.

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
