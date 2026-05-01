Helper scripts for Endure development.

## CI / audit scripts

- `check-forbidden-patterns.sh` — validates no Bittensor/Wormhole/stripped-contract identifiers in `packages/contracts/src/`
- `check-stance-b.sh` — Stance B byte-identical audit. Verifies vendored Venus production Solidity, test infrastructure (with documented patches), TS helpers + scripts, and `lib/venusprotocol-*` version manifest consistency against the upstream pin. Exits non-zero on any undocumented divergence. See `packages/contracts/FORK_MANIFEST.md` for the documented-deviation register.
- `check-test-mapping.sh` — verifies every Foundry test deleted between `main` and `HEAD` has a corresponding mapping row in `docs/briefs/phase-0.5-venus-rebase-test-mapping.md`. Discovery is dynamic via `git diff --diff-filter=D`.
- `check-hardhat-skips.sh` — drift detector that asserts the `EXCLUDED_TEST_DIRS` + `EXCLUDED_TEST_FILES` arrays in `packages/contracts/hardhat.config.ts` exactly match the file list in `packages/contracts/tests/hardhat/SKIPPED.md`.
- `gas-snapshot-check.sh` — CI guard that runs `forge snapshot --check` from the correct working directory.

## End-to-end smoke

- `e2e-smoke.sh` — live-chain end-to-end validation. Run after `DeployLocal.s.sol` against Anvil; exercises supply → borrow → repay → redeem → direct liquidation against the Venus chassis. Asserts each step's expected state transition; non-zero exit on any failure.

### Local reproduction

The deploy helper exceeds the EIP-170 contract-size limit (~125KB), so Anvil and the forge script both need overrides:

```bash
anvil --silent --disable-code-size-limit --gas-limit 1000000000 &
(cd packages/deploy && forge script src/DeployLocal.s.sol \
    --rpc-url http://localhost:8545 --broadcast --slow --legacy \
    --code-size-limit 999999)
bash scripts/e2e-smoke.sh
```

`--code-size-limit 999999` on the forge invocation is required even though `packages/deploy/foundry.toml` sets `code_size_limit = 999999` (the config setting alone does not override forge's CLI-default check on forge 1.2.x).
