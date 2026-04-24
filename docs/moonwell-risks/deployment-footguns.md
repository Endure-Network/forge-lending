# Moonwell/Compound-V2 deployment footguns

Endure-specific footguns that Moonwell's upstream docs do not flag prominently. Derived from Phase 0 strip-and-deploy work. Read before any market listing, cap change, or upgrade.

## `borrowCap = 0` means UNLIMITED, not disabled

This is the single most dangerous default in Moonwell/Compound V2 semantics.

- `supplyCap = 0` → unlimited (documented)
- `borrowCap = 0` → **unlimited** (undocumented in upstream comments; catastrophic if misread)

To actually disable borrowing on a market, use one of:

| Option | How | When |
|---|---|---|
| `borrowCap = 1` (1 wei) | `comptroller._setMarketBorrowCaps([mToken], [1])` | Endure uses this for alpha markets (Phase 0) |
| `borrowGuardianPaused[mToken] = true` | `comptroller._setBorrowPaused(mToken, true)` | When a market needs temporary borrow-only pause |
| `borrowCap = type(uint256).max` | `comptroller._setMarketBorrowCaps([mToken], [type(uint256).max])` | Equivalent to `0` but explicit — Endure uses this for mWTAO to signal "unlimited is intentional" |

**Phase 0 actual config**:
- `mMockAlpha30`, `mMockAlpha64`: `borrowCap = 1` (blocked; collateral-only markets)
- `mWTAO`: `borrowCap = type(uint256).max` (unlimited by design; TAO is the sole borrowable)

## Atomic market listing — the canonical sequence

A new market must be fully configured in a single transaction (or a single timelock execution). The order matters:

1. Deploy `MErc20Delegator` with `MErc20Delegate` as implementation
2. Deploy `JumpRateModel` with curve parameters (pass to delegator constructor)
3. Call `Comptroller._supportMarket(mToken)` — **MUST come before any user interaction**
4. Call `MockPriceOracle.setUnderlyingPrice(mToken, priceMantissa)` — **MUST come before `_setCollateralFactor`** (Comptroller rejects CF change if oracle returns 0)
5. Call `Comptroller._setCollateralFactor(mToken, cf)`
6. Call `Comptroller._setMarketSupplyCaps([mToken], [cap])`
7. Call `Comptroller._setMarketBorrowCaps([mToken], [cap])`
8. Call `mToken._setReserveFactor(rf)`
9. Call `mToken._setInterestRateModel(irm)` if not set in constructor
10. **Admin seed deposit + burn** (see `empty-market-donation.md`)

Moonwell's `mip-b00.sol` is the upstream template. Endure's implementation lives in `packages/contracts/test/helper/EndureDeployHelper.sol::_listMarket` and is exercised by `packages/deploy/src/DeployLocal.s.sol`.

**Do not reorder**. Each step above has a dependency on prior steps. Steps 4 and 5 especially — skipping the oracle price before `_setCollateralFactor` causes a silent rejection, not a hard revert, in Compound's error-code style.

## Compound-style soft failures (`Failure(error, info, detail)`)

Moonwell inherits Compound V2's error-code pattern. Many operations return status code 0 (success) or non-zero (failure) **without reverting**. They emit `Failure(uint error, uint info, uint detail)` (topic `0x45b96fe4...`) instead.

Implications:

- `cast send` returns `status: 1` even when the operation failed. You MUST parse logs for the Failure topic.
- Transaction receipts don't tell you success — event logs do.
- Our `scripts/e2e-smoke.sh` fails loudly on any Failure event; use it as the operator's lifeline.

Common error/info combos and their real meaning (from `src/TokenErrorReporter.sol`):

| error | info | Meaning |
|---|---|---|
| `14` (TOKEN_INSUFFICIENT_CASH) | `9` (BORROW_CASH_NOT_AVAILABLE) | Market literally has no underlying to lend; not a permissions issue |
| `3` (COMPTROLLER_REJECTION) | `14` (BORROW_COMPTROLLER_REJECTION) | `detail` carries a Comptroller error code (e.g., 4=INSUFFICIENT_LIQUIDITY, 13=PRICE_ERROR) |

`fail()` always emits `detail = 0`. `failOpaque()` carries the external-contract error in `detail`. If `detail != 0`, the rejection came from a collaborator (usually Comptroller); if `detail == 0`, it came from MToken internals.

## Supply and borrow cap — Endure tier-1 configuration

| Parameter | Endure Phase 3/4 initial | Rationale |
|---|---|---|
| `collateralFactorMantissa` | 0.20–0.25e18 (tier-1 alpha) | Conservative for 50%+ daily volatility |
| `liquidationIncentiveMantissa` | 1.08e18 (8% liquidator bonus + 2% protocol seize) | Standard Compound range; competitive with keeper gas |
| `closeFactorMantissa` | 0.50e18 | Compound default |
| `supplyCap` | 10,000 alpha per market initially | Caps protocol exposure per subnet |
| `borrowCap` (alpha markets) | 1 wei | Enforces TAO-only borrow at the cap level |
| `borrowCap` (TAO market) | `type(uint256).max` | TAO is the sole borrowable; scale as supply grows |
| `reserveFactorMantissa` | 0.15e18 (15%) | Build insurance fund from interest revenue |

## Upgradeability posture

- Moonwell v2 uses `Unitroller` proxy + `Comptroller` logic for upgrade. MVP Endure CAN use this pattern.
- Individual `MErc20Delegator` markets are upgradeable to new `MErc20Delegate` implementations via `_setImplementation`.
- **MVP recommendation**: ship Phase 4 with upgrade capability but behind the timelock with pause-only-admin. No upgrade authority at mainnet launch. Revisit post-audit.

## Diff hygiene with upstream

Moonwell ships security patches (e.g., after the November 2025 Chainlink incident). To backport cleanly:

1. Keep a `upstream` git remote pointing at `moonwell-fi/moonwell-contracts-v2`
2. Document every Endure-specific divergence in `packages/contracts/FORK_MANIFEST.md`
3. Periodically `git diff upstream/main -- src/` and review for fixes worth backporting
4. BSD-3 permits backporting freely; no license conversation needed

**Stance B discipline**: kept core Moonwell files must stay byte-identical to our pinned upstream commit. Any edit requires documenting in FORK_MANIFEST.md Section 5 (Unresolved Deviations). This is enforced by `scripts/check-forbidden-patterns.sh` for stripped-contract references and by spot-check SHA-256 comparisons for retained files.

## Common mistakes (and how they bite)

| Mistake | Consequence | Fix |
|---|---|---|
| Forgetting admin seed at market listing | Empty-market donation attack vector | Atomic listing tx includes seed + burn; see `empty-market-donation.md` |
| Setting `borrowCap = 0` thinking it disables borrow | Actually unlimited; catastrophic for alpha markets | Use `borrowCap = 1` or pause guardian |
| Calling `MErc20.mint` before `Comptroller._supportMarket` | Reverts, unhelpful error | Deploy script must sequence correctly; use `EndureDeployHelper._listMarket` |
| Setting collateral factor before oracle price | Silent `Failure` emission, CF stays 0 | Order: oracle price → CF (our sequence in step 4/5 above) |
| Using Chainlink feed for alpha price | Alpha has no Chainlink feed | Build `EnduOracle` from first principles using subnet AMM reserves (Phase 3) |
| Not stripping Wormhole deps before `forge build` | Compile errors from missing Wormhole contracts | Strip governance layer first, then run `forge build` |
| Importing from `@moonwell/` paths after fork | Phantom dependencies | Rewrite imports to `@protocol/` remapping in Phase 0 (done) |
| Treating `cast send status: 1` as success | Missed Compound soft-failures | Always grep tx logs for `0x45b96fe4...` Failure topic |
