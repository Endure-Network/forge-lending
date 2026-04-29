# Endure Fork Manifest

This manifest tracks every divergence from upstream sources. The protocol uses Venus Protocol Core Pool as its chassis.

## 1. Upstream
- **Repository**: `VenusProtocol/venus-protocol`
- **Pinned Commit**: `6400a067114a101bd3bebfca2a4bd06480e84831`
- **Tag**: `v10.2.0-dev.5`

## 2. Vendored Files (Stance B)
All files under `src/` (excluding `src/endure/`) are byte-identical to the upstream repository at the pinned commit. Every file under `src/` must hash-match the corresponding file at `<venus>/contracts/<same-relative-path>`.

## 3. Endure-authored Files
Located in `src/endure/`:
- `MockResilientOracle.sol`
- `AllowAllAccessControlManager.sol`
- `DenyAllAccessControlManager.sol`
- `MockXVS.sol`
- `MockAlpha30.sol`
- `MockAlpha64.sol`
- `WTAO.sol`
- `EnduRateModelParams.sol`

## 4. Test Helpers
Located in `src/test-helpers/venus/`:
- These files were moved from the upstream `test/` directory to support the Endure test suite.
- Three harness files have documented import path deviations (see section 5).

## 5. Documented Deviations
The following 3 harness files were re-vendored from Venus upstream with single-line import path patches to resolve under Endure's layout:

| File | Original import (upstream) | Patched import (Endure) |
|------|---------------------------|------------------------|
| `src/test-helpers/venus/VRTConverterHarness.sol` | `../../contracts/Tokens/VRT/VRTConverter.sol` | `../../venus-staging/Tokens/VRT/VRTConverter.sol` |
| `src/test-helpers/venus/VRTVaultHarness.sol` | `../../contracts/VRTVault/VRTVault.sol` | `../../venus-staging/VRTVault/VRTVault.sol` |
| `src/test-helpers/venus/XVSVestingHarness.sol` | `../../contracts/Tokens/XVS/XVSVesting.sol` | `../../venus-staging/Tokens/XVS/XVSVesting.sol` |

*Note: The paths were updated during the staging phase; in the steady-state Venus layout, these resolve relative to the `src/` root.*

## 6. lib/ Packages (External Dependencies)
The following 5 `@venusprotocol/*` packages are vendored byte-identical under `lib/venusprotocol-*/`.

| Package | Version | Git repo | Commit SHA |
|---------|---------|----------|------------|
| `lib/venusprotocol-governance-contracts/` | `2.13.0` | `VenusProtocol/governance-contracts` | `f8d3efe9578c8cd11330181bb4396f6b449e654c` |
| `lib/venusprotocol-oracle/` | `2.10.0` | `VenusProtocol/oracle` | `c4bd1d95b5989c8f8938812471ab715df77c6b1e` |
| `lib/venusprotocol-protocol-reserve/` | `3.4.0` | `VenusProtocol/protocol-reserve` | `80c53be90a70d9d4704efa33876dc77c0f48f8b2` |
| `lib/venusprotocol-solidity-utilities/` | `2.1.0` | `VenusProtocol/solidity-utilities` | `d891bec6e60338132994560b9d47f2865ee33e0d` |
| `lib/venusprotocol-token-bridge/` | `2.7.0` | `VenusProtocol/token-bridge` | `845a6fa27a0fde98ce6ad621f2340b247d23c866` |

## 7. Stance B Audit Posture
To verify byte-identity:
1. Identify the file in `src/`.
2. Locate the corresponding file in the `VenusProtocol/venus-protocol` repository at the pinned commit.
3. Compute the SHA-256 hash of both files.
4. If the hashes match, byte-identity is confirmed.
