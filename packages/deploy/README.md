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

`DeployWithOptionals.s.sol` keeps the default deployment unchanged and writes a separate `addresses-optionals.json` for opt-in consumers. XVS rewards are the first supported optional path:

```bash
ENABLE_XVS=true forge script src/DeployWithOptionals.s.sol \
    --rpc-url http://localhost:8545 --broadcast --slow --legacy \
    --code-size-limit 999999
```

Optional XVS configuration knobs:

- `XVS_FUNDING_AMOUNT` — amount of mock XVS to fund the Comptroller with, default `1000e18`.
- `XVS_VWTAO_SUPPLY_SPEED` — vWTAO supply reward speed, default `1e18`.
- `XVS_VWTAO_BORROW_SPEED` — vWTAO borrow reward speed, default `0`.

`ENABLE_VAI`, `ENABLE_LIQUIDATOR`, and `ENABLE_PRIME` are reserved for later optional paths and currently fail fast with a clear message if enabled.

## Hardhat alternative

A parallel Hardhat-side deploy lives at `packages/contracts/scripts/deploy-local.ts`. It targets `pnpm hardhat node` (in-process or `localhost` network) and writes the same 16-key `addresses.json` schema by deploying the same `EndureDeployHelper` Solidity contract. Frontend and integration consumers that prefer the Hardhat toolchain (e.g., Next.js dev with ethers/viem) can use:

```bash
pnpm hardhat node                                                            # one terminal
cd packages/contracts && pnpm hardhat run scripts/deploy-local.ts --network localhost
cd packages/contracts && pnpm hardhat run scripts/smoke-local.ts  --network localhost
```

Both deploy paths produce identical contract addresses (deterministic deployer + nonce sequence) and exercise identical Solidity logic. See `FORK_MANIFEST.md` §4.3 for the rationale behind disabling `hardhat-deploy` auto-run and providing this on-demand replacement.
