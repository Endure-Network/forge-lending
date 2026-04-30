# Optional Prime Deployment Guide

Prime is disabled in the default Endure local deployment. Enable it through `DeployWithOptionals.s.sol` so `DeployLocal.s.sol` and the default `addresses.json` schema stay unchanged.

## Foundry local deploy

Prime depends on a local XVS token and XVSVault pool. `ENABLE_PRIME=true` automatically enables the local XVS optional path so the vault has a reward/staking token:

```bash
cd packages/deploy
ENABLE_PRIME=true forge script src/DeployWithOptionals.s.sol \
  --rpc-url http://localhost:8545 --broadcast --slow --legacy \
  --code-size-limit 999999
```

The script writes `packages/deploy/addresses-optionals.json` with `prime`, `primeImplementation`, `primeLiquidityProvider`, `primeLiquidityProviderImplementation`, `xvsVault`, `xvsVaultImplementation`, and `xvsStore` in addition to the core addresses.

## Configuration knobs

- `PRIME_BLOCKS_PER_YEAR` — block-based Prime/PLP year length, default `100` for local testing.
- `PRIME_STAKING_PERIOD` — seconds a user must stake before claiming Prime, default `600`.
- `PRIME_MINIMUM_STAKED_XVS` — minimum XVS stake, default `1000e18`.
- `PRIME_MAXIMUM_XVS_CAP` — maximum XVS counted in score calculations, default `100000e18`.
- `PRIME_XVS_VAULT_POOL_ID` — XVSVault pool id, default `0`.
- `PRIME_XVS_VAULT_REWARD_PER_BLOCK` — local XVSVault reward rate, default `1e18`.
- `PRIME_XVS_VAULT_LOCK_PERIOD` — XVSVault withdrawal lock period, default `300`.
- `PRIME_ALPHA_NUMERATOR` / `PRIME_ALPHA_DENOMINATOR` — Prime alpha ratio, defaults `1 / 2`.
- `PRIME_LOOPS_LIMIT` — Max loops limit for Prime/PLP, default `20`.
- `PRIME_IRREVOCABLE_LIMIT` / `PRIME_REVOCABLE_LIMIT` — mint limits, defaults `1000 / 1000`.
- `PRIME_VWTAO_SUPPLY_MULTIPLIER` / `PRIME_VWTAO_BORROW_MULTIPLIER` — initial vWTAO Prime market multipliers, defaults `1e18 / 1e18`.

## Wiring sequence

The optional helper keeps the legacy Venus vault pieces out of the default deploy path:

1. Deploy legacy `XVSStore`, `XVSVaultProxy`, and `XVSVault` from bytecode artifacts.
2. Upgrade the vault proxy to the XVSVault implementation.
3. Configure XVS store, access control, time manager, store owner, and the initial XVS vault pool.
4. Deploy `PrimeLiquidityProvider` and `Prime` implementations plus transparent proxies.
5. Initialize PLP, initialize Prime, and run `Prime.initializeV2(address(0))` for core-pool-only local deployments.
6. Wire PLP → Prime and XVSVault → Prime callbacks.
7. Set Prime mint limits, add the initial vWTAO Prime market, register Prime on the Comptroller, and unpause Prime.

The Core Pool Diamond must route `setPrimeToken(address)` and `_setPrimeToken(address)` to `SetterFacet`; `DiamondSelectorRouting.t.sol` covers both selectors.
