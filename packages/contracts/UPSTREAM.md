# Upstream Attribution

This package is a fork of [VenusProtocol/venus-protocol](https://github.com/VenusProtocol/venus-protocol).

- **License**: BSD-3-Clause
- **Pinned Commit**: `6400a067114a101bd3bebfca2a4bd06480e84831`
- **Tag**: `v10.2.0-dev.5`

## Synchronization Policy

Endure maintains Stance B (byte-identical vendoring) for all Venus source files under `src/` excluding `src/endure/` and `src/test-helpers/venus/`. See `FORK_MANIFEST.md` for the full audit trail.

## Endure-specific Additions

New contracts in `src/endure/`:
- `MockResilientOracle.sol` — mock oracle implementing ResilientOracleInterface
- `AllowAllAccessControlManager.sol` — allow-all ACM for testing
- `DenyAllAccessControlManager.sol` — deny-all ACM for negative-path tests
- `MockXVS.sol` — mock XVS ERC20 for reward path testing
- `MockAlpha30.sol`, `MockAlpha64.sol` — mock collateral tokens
- `WTAO.sol` — mock Wrapped TAO (borrow asset)
- `EnduRateModelParams.sol` — IRM constants for Venus TwoKinks shape

## External Dependencies

The following Venus external dependency packages are vendored byte-identical under `lib/venusprotocol-*/`:

| Package | Version |
|---------|---------|
| `@venusprotocol/governance-contracts` | `2.13.0` |
| `@venusprotocol/oracle` | `2.10.0` |
| `@venusprotocol/protocol-reserve` | `3.4.0` |
| `@venusprotocol/solidity-utilities` | `2.1.0` |
| `@venusprotocol/token-bridge` | `2.7.0` |
