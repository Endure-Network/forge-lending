Helper scripts for Endure development.

- `check-forbidden-patterns.sh` — validates no Bittensor/Wormhole/stripped-contract identifiers in `packages/contracts/src/`
- `gas-snapshot-check.sh` — CI guard that runs `forge snapshot --check` from the correct working directory
- `e2e-smoke.sh` — live-chain end-to-end validation (run after `DeployLocal.s.sol` against Anvil); exercises supply → borrow → repay → redeem → direct liquidation against the Venus chassis. The script asserts each step's expected state transition; non-zero exit on any failure.
