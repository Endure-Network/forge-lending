# Endure Phase 0 Issues

## [2026-04-24] Initial - No issues yet

## [2026-04-24] Tasks 12-13

- Local `forge config --root packages/contracts --json` resolves `evm_version` as `paris` despite `packages/contracts/foundry.toml` explicitly setting `shanghai`; file-level config is correct, but toolchain behavior should be validated separately if strict config introspection matters.
- `forge build --root packages/contracts` still fails after the first cascade cleanup because `packages/contracts/src/4626/Factory4626.sol` imports deleted `@protocol/4626/MoonwellERC4626.sol`. Additional 4626 cascade pruning is still required.

- Solidity LSP diagnostics were unavailable in this environment (`.sol` has no configured LSP server), so verification relied on `forge build --root packages/contracts` rather than editor diagnostics for Solidity files.

## [2026-04-24] Task 20 deploy script quirks

- In this Foundry version, the task's literal root-level command (`forge script --root packages/deploy src/DeployLocal.s.sol --rpc-url ... --broadcast`) did not work as written: the CLI rejected the path without an explicit target contract, and broadcasting required an explicit wallet (`--private-key` for Anvil). Verified path instead: run from `packages/deploy/` with `src/DeployLocal.s.sol:DeployLocal` plus the Anvil private key.

## [2026-04-24] Tasks 23-24 verification caveats

- Solidity LSP diagnostics could not be run for the changed `.sol` files because this environment has no Solidity LSP server configured; verification used fresh `forge build` and `forge test` runs instead.
