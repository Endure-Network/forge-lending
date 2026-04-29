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
