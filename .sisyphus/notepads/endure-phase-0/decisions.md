# Endure Phase 0 Decisions

## [2026-04-24] Initial

### Governance
- Phase 0: Deployer EOA as admin on all 5 admin slots
- Phase 4: Timelock + GovernorBravo (deferred)
- NO custom multisig in Phase 0

### Mock Token Decimals
- All 3 mocks (WTAO, MockAlpha30, MockAlpha64): 18 decimals

### Oracle Prices (TAO-denominated, 18-dec)
- mWTAO: 1e18 (constant)
- mMockAlpha30: 1e18 (drops to 3e17 in liquidation test)
- mMockAlpha64: 1e18

### Market Parameters
- CLOSE_FACTOR = 0.5e18
- LIQUIDATION_INCENTIVE = 1.08e18
- COLLATERAL_FACTOR_ALPHA = 0.25e18
- COLLATERAL_FACTOR_WTAO = 0
- SUPPLY_CAP_ALPHA = 10_000e18
- BORROW_CAP_ALPHA = 1 (1 wei, NOT 0!)
- BORROW_CAP_WTAO = type(uint256).max
- RESERVE_FACTOR = 0.15e18
- SEED_AMOUNT = 1e18

### Invariant Profile
- runs = 1000, depth = 50, fail_on_revert = false

### Commit Strategy
- 7 total commits across 5 waves
- Wave 1: 1 commit (Tasks 1-7)
- Wave 2: 2 commits (Task 8 standalone, Tasks 9-14 joint)
- Wave 3: 1 commit (Tasks 15-19)
- Wave 4: 2 commits (Task 20 standalone, Tasks 21-24 joint)
- Wave 5: 1 commit (Tasks 25-27)

## [2026-04-24] Tasks 12-13 cleanup choices

- Preserved Stance B by restoring only the rewards contracts required by kept core `ComptrollerStorage.sol`; no kept core lending `.sol` file was modified.
- Rewrote `packages/contracts/remappings.txt` to the Endure-only set and removed `@wormhole/` / `@proposals/` instead of reintroducing upstream remappings.
- Simplified `packages/contracts/test/helper/BaseTest.t.sol` to a minimal `forge-std/Test` base rather than deleting the helper file, satisfying the requirement to keep the path while removing stripped-contract dependencies.

- Kept Stance B intact by avoiding any edits to kept core lending source files and resolving missing imports through a mix of upstream restoration (required rewards contracts) and deletion of non-core cascades (views, ERC4626 wrappers/factories, cypher, and stripped test suites).
- Narrowed the retained Solidity test surface to the core lending-oriented unit tests (`Comptroller`, `MErc20`, `MErc20Delegate`, `Oracle`) plus supporting helpers/mocks so `forge build` could succeed without reintroducing stripped governance/Wormhole modules.

## [2026-04-24] Task 20 deploy package choices

- Kept `DeployLocal.s.sol` chain-locked to Anvil (`31337`) and enforced Phase 0 admin semantics by requiring `ADMIN_EOA == deployer` during broadcast.
- Wrote `packages/deploy/broadcast/addresses.json` directly from the script after `_deploy()` so the local deploy artifact always includes the 13 deployed contract addresses plus deployer/role metadata.
- Added deploy-package `allow_paths = ["../contracts"]` so `packages/deploy` can compile against the sibling Foundry package instead of copying helper logic locally.
