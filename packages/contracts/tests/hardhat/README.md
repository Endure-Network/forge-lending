# Hardhat Tests (Venus Upstream)

This directory contains Hardhat test files vendored byte-identical from Venus Protocol Core Pool at commit `6400a067114a101bd3bebfca2a4bd06480e84831` (tag: `v10.2.0-dev.5`).

These tests run against the full Venus fixture infrastructure (VAI, Prime, XVS, VRT, Liquidator, Swap, DelegateBorrowers) and serve as Endure's upstream compatibility verification. They are NOT Endure's own tests — those live in `test/endure/`.

**Excluded**: `Fork/` subdirectory (requires BSC mainnet RPC — not portable).

**Run**: `pnpm --filter @endure/contracts hardhat test`
