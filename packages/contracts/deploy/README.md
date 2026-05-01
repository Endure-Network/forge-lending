# Hardhat Deploy Scripts (Venus Upstream)

This directory contains hardhat-deploy scripts vendored byte-identical from Venus Protocol Core Pool at commit `6400a067114a101bd3bebfca2a4bd06480e84831` (tag: `v10.2.0-dev.5`).

These scripts set up VAI/Prime/XVS/VRT/Liquidator/Swap/DelegateBorrowers fixtures during Hardhat tests. They are **Hardhat-fixture-only** — NOT consumed by Endure's Foundry/Anvil deployment pipeline.

**Foundry deployment**: See `packages/deploy/src/DeployLocal.s.sol` (entirely separate path; the two systems DO NOT share deployment state).
