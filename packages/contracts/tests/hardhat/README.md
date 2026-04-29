# Hardhat Tests (Venus Upstream)

This directory contains Hardhat test files vendored byte-identical from Venus Protocol Core Pool at commit `6400a067114a101bd3bebfca2a4bd06480e84831` (tag: `v10.2.0-dev.5`).

These tests run against the full Venus fixture infrastructure (VAI, Prime, XVS, VRT, Liquidator, Swap, DelegateBorrowers) and serve as Endure's upstream compatibility verification. They are NOT Endure's own tests — those live in `test/endure/`.

**Excluded**: `Fork/` subdirectory (requires BSC mainnet RPC — not portable).

**Run**: `pnpm --filter @endure/contracts hardhat test`

## Path Mapping

Hardhat is configured with `paths.sources = "./src"`. Solidity contracts are compiled from `packages/contracts/src/`.

**Import resolution**: `@venusprotocol/*` and `@openzeppelin/*` packages are resolved via symlinks from `node_modules/` to `lib/`. The `scripts/link-hardhat-libs.sh` postinstall script creates these symlinks. If Hardhat fails with `HH411` ("library not installed"), run:

```bash
pnpm --filter @endure/contracts run postinstall
```

Each `lib/venusprotocol-*` directory has a minimal `package.json` to satisfy Node.js module resolution.

**Running individual tests**:

```bash
pnpm --filter @endure/contracts hardhat test tests/hardhat/<subsystem>/<file>.ts
```

**ethers version**: Tests use ethers v5 (`@nomiclabs/hardhat-ethers`), not v6. The `@defi-wonderland/smock` mocking library requires this.
