# Empty-market first-deposit donation attack

**Status**: Phase 0 ships the first leg (admin seed deposit + burn). Phase 4 ships the deeper fix (round-in-protocol-favor).

**Severity**: Critical. This class of vulnerability has cost multiple Compound V2 forks millions of dollars. Sonne lost $20M to this on May 14, 2024. Canonical Compound V2 (and Moonwell, Benqi, Sonne, Venus Core) are all vulnerable upstream. The vulnerability is NOT patched in Moonwell's upstream as of our pin commit `8d5fb11`.

## The attack

1. Market is empty (no supply, no borrow). `totalSupply = 0`, `exchangeRate = initialExchangeRateMantissa` (typically `2e18`).
2. Attacker calls `mint(1)` — mints 1 wei of mToken.
3. Attacker directly transfers a large amount of underlying to the mToken contract (bypassing `mint`). This inflates `totalCash` without minting shares.
4. `exchangeRate = totalCash / totalSupply` is now enormous.
5. Victim calls `mint(smallAmount)` — `mintTokens = smallAmount / exchangeRate` rounds to 0. Victim loses their deposit.
6. Attacker redeems 1 mToken, gets all the underlying.

## The Endure fix (three mitigations, all needed)

### A. Admin seed deposit + burned MINIMUM_LIQUIDITY (Uniswap V2 pattern) — Phase 0

- At market initialization, admin mints a small amount (e.g., 1e18 wei of underlying, which is 1 whole token with 18-decimal mocks)
- The resulting mTokens are sent to `address(0xdEaD)`, permanently locking them
- This establishes a floor so `totalSupply > 0` always, and direct donations dilute across existing shares

**Phase 0 implementation**: `EndureDeployHelper._listMarket()` does exactly this. Tests: `test/endure/SeedDeposit.t.sol` verifies `totalSupply > 0` and `0xdEaD` holds the expected mToken amount on every market.

### B. Round in protocol favor — Phase 4

- In `redeemFresh`: when computing `redeemAmount = redeemTokens × exchangeRate`, current Compound math rounds DOWN on the amount. This leaves dust in the protocol — fine for redemption.
- In `mintFresh`: when computing `mintTokens = mintAmount / exchangeRate`, current math rounds DOWN on tokens. This is SAFE (user gets fewer tokens). Keep.
- **The bug**: when redeeming 1.999 tokens, the user currently receives `floor(1.999 × rate)`. If the attacker can make `exchangeRate` huge enough, this rounding creates arbitrage opportunities. Defensive fix: check that `redeemAmount * totalSupply / totalCash ≥ redeemTokens` (i.e., the redemption doesn't implicitly round the exchange rate against the protocol).

### C. Virtual shares (Aave-style, optional) — Phase 4 consideration

- Aave V3 adds a constant "virtual" share count to `totalSupply` in rate calculations, preventing the rate from becoming abusable.
- More invasive change; mitigations A+B are usually sufficient.

## Implementation locations for Phase 4

- `src/MToken.sol` — `initialize()`, `exchangeRateStoredInternal()`, `redeemFresh()`
- Targeted invariant tests required:
  - Exchange rate can only increase or stay flat (except via reserve factor)
  - No path from any user action produces share-count rounding advantage
  - `redeemFresh` with arbitrary `redeemTokens` never over-pays relative to `totalCash * redeemTokens / totalSupply`

## References

- Sonne post-mortem (May 2024): [public incident report](https://sonnefinance.medium.com/) — exploit chain matches this class exactly
- OpenZeppelin advisory on Compound V2 empty-market donation: https://blog.openzeppelin.com
- Aave V3 virtual-shares implementation: `aave/aave-v3-core` `ReserveLogic.sol`
- Upstream Moonwell discussion (none as of 8d5fb11): no corresponding upstream patch to backport yet; track `moonwell-fi/moonwell-contracts-v2` issues for any future remediation
