`DeployLocal.s.sol` atomically deploys Endure Phase 0 to local Anvil (chainId 31337). NOT idempotent — fresh Anvil per run.

## Running

The deploy helper (`EndureDeployHelper`) exceeds the EIP-170 contract-size limit (~125KB), so both Anvil and the forge script need overrides:

```bash
anvil --silent --disable-code-size-limit --gas-limit 1000000000 &
forge script src/DeployLocal.s.sol \
    --rpc-url http://localhost:8545 --broadcast --slow --legacy \
    --code-size-limit 999999
```

`--code-size-limit 999999` on the forge invocation is required even though `foundry.toml` sets `code_size_limit = 999999` (the config setting alone does not override forge's CLI-default check on forge 1.2.x).

After deploy completes, `addresses.json` is written to this directory and consumed by `scripts/e2e-smoke.sh`.

## Optional modules

`DeployWithOptionals.s.sol` keeps the default deployment unchanged and writes a separate `addresses-optionals.json` for opt-in consumers. XVS rewards, VAI, the Liquidator, and Prime are supported optional paths:

```bash
ENABLE_XVS=true forge script src/DeployWithOptionals.s.sol \
    --rpc-url http://localhost:8545 --broadcast --slow --legacy \
    --code-size-limit 999999
```

Optional XVS configuration knobs:

- `XVS_FUNDING_AMOUNT` — amount of mock XVS to fund the Comptroller with, default `1000e18`.
- `XVS_VWTAO_SUPPLY_SPEED` — vWTAO supply reward speed, default `1e18`.
- `XVS_VWTAO_BORROW_SPEED` — vWTAO borrow reward speed, default `0`.

Optional VAI deployment:

```bash
ENABLE_VAI=true forge script src/DeployWithOptionals.s.sol \
    --rpc-url http://localhost:8545 --broadcast --slow --legacy \
    --code-size-limit 999999
```

VAI configuration knobs:

- `VAI_MINT_RATE` — collateral value basis points available for VAI minting, default `5000`.
- `VAI_MINT_CAP` — global VAI supply cap, default `1000000e18`.
- `VAI_RECEIVER` — stability-fee receiver, default deployer.
- `VAI_TREASURY_GUARDIAN` — VAI treasury guardian, default deployer.
- `VAI_TREASURY_ADDRESS` — VAI mint-fee treasury, default deployer.
- `VAI_TREASURY_PERCENT` — mint fee percentage scaled by `1e18`, default `0`.
- `VAI_BASE_RATE` — base stability fee scaled by `1e18`, default `0`.
- `VAI_FLOAT_RATE` — floating stability fee scaled by `1e18`, default `0`.

Optional Liquidator deployment requires VAI because the upstream Liquidator reads VAI debt during liquidation checks:

```bash
ENABLE_VAI=true ENABLE_LIQUIDATOR=true forge script src/DeployWithOptionals.s.sol \
    --rpc-url http://localhost:8545 --broadcast --slow --legacy \
    --code-size-limit 999999
```

Liquidator configuration knobs:

- `LIQUIDATOR_TREASURY_PERCENT` — treasury share scaled by `1e18`, default `0.05e18`.
- `LIQUIDATOR_MIN_LIQUIDATABLE_VAI` — minimum VAI debt for the VAI liquidation path, default `0`.
- `LIQUIDATOR_PENDING_REDEEM_CHUNK_LENGTH` — pending redemption chunk size, default `10`.

Optional Prime deployment automatically enables the local XVS path because Prime needs an XVS token and XVSVault pool:

```bash
ENABLE_PRIME=true forge script src/DeployWithOptionals.s.sol \
    --rpc-url http://localhost:8545 --broadcast --slow --legacy \
    --code-size-limit 999999
```

Prime configuration knobs:

- `PRIME_BLOCKS_PER_YEAR` — local block-based year length, default `100`.
- `PRIME_STAKING_PERIOD` — seconds a user must stake before claiming Prime, default `600`.
- `PRIME_MINIMUM_STAKED_XVS` — minimum XVS stake, default `1000e18`.
- `PRIME_MAXIMUM_XVS_CAP` — maximum XVS counted in scores, default `100000e18`.
- `PRIME_XVS_VAULT_POOL_ID` — XVSVault pool id, default `0`.
- `PRIME_XVS_VAULT_REWARD_PER_BLOCK` — local vault reward rate, default `1e18`.
- `PRIME_XVS_VAULT_REWARD_FUNDING_AMOUNT` — mock XVS amount transferred into XVSStore for local vault rewards, default `1000e18`.
- `PRIME_XVS_VAULT_LOCK_PERIOD` — vault withdrawal lock period, default `300`.
- `PRIME_ALPHA_NUMERATOR` / `PRIME_ALPHA_DENOMINATOR` — Prime alpha ratio, defaults `1 / 2`.
- `PRIME_LOOPS_LIMIT` — Max loops limit, default `20`.
- `PRIME_IRREVOCABLE_LIMIT` / `PRIME_REVOCABLE_LIMIT` — mint limits, defaults `1000 / 1000`.
- `PRIME_VWTAO_SUPPLY_MULTIPLIER` / `PRIME_VWTAO_BORROW_MULTIPLIER` — initial vWTAO Prime market multipliers, defaults `1e18 / 1e18`.

## Hardhat alternative

A parallel Hardhat-side deploy lives at `packages/contracts/scripts/deploy-local.ts`. It targets `pnpm hardhat node` (in-process or `localhost` network) and writes the same 16-key `addresses.json` schema by deploying the same `EndureDeployHelper` Solidity contract. Frontend and integration consumers that prefer the Hardhat toolchain (e.g., Next.js dev with ethers/viem) can use:

```bash
pnpm hardhat node                                                            # one terminal
cd packages/contracts && pnpm hardhat run scripts/deploy-local.ts --network localhost
cd packages/contracts && pnpm hardhat run scripts/smoke-local.ts  --network localhost
```

Both deploy paths produce identical contract addresses (deterministic deployer + nonce sequence) and exercise identical Solidity logic. See `FORK_MANIFEST.md` §4.3 for the rationale behind disabling `hardhat-deploy` auto-run and providing this on-demand replacement.
