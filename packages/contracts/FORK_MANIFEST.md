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
- `AllowAllAccessControlManager.sol`
- `DenyAllAccessControlManager.sol`
- `EnduRateModelParams.sol`
- `EndureRoles.sol`
- `MockAlpha30.sol`
- `MockAlpha64.sol`
- `MockResilientOracle.sol`
- `MockXVS.sol`
- `WTAO.sol`

## 4. Test Infrastructure (Steady State)

### 4.1 Vendored Helpers (Byte-identical)
The following TypeScript helpers were vendored from Venus `6400a067` into `packages/contracts/` to support the dual-toolchain test suite. These are byte-identical to upstream:
- `helpers/chains.ts`
- `helpers/deploymentConfig.ts`
- `helpers/utils.ts`
- `helpers/markets/types.ts`
- `script/deploy/comptroller/diamond.ts`

### 4.2 Vendored Solidity Helpers (Byte-identical)
All files in `src/test-helpers/venus/` (excluding those listed in §5.3) are byte-identical to their upstream counterparts in the Venus `contracts/test-helpers/` or `test/` directories.

## 5. Documented Deviations

### 5.1 Import Path Patches (Solidity)
The following 7 files were re-vendored from Venus upstream with single-line import path patches to resolve under Endure's layout (pointing `../../` to the remapped `src/` root):

| File | Patched Imports |
|------|-----------------|
| `src/test-helpers/venus/ComptrollerHarness.sol` | `./ComptrollerMock.sol`, `../../Comptroller/Unitroller.sol` |
| `src/test-helpers/venus/ComptrollerMock.sol` | `../../Comptroller/Diamond/facets/*Facet.sol`, `../../Comptroller/Unitroller.sol` |
| `src/test-helpers/venus/ComptrollerScenario.sol` | `./ComptrollerMock.sol` |
| `src/test-helpers/venus/VBep20Harness.sol` | `../../Tokens/VTokens/*.sol`, `./ComptrollerScenario.sol` |
| `src/test-helpers/venus/VRTConverterHarness.sol` | `../../Tokens/VRT/VRTConverter.sol` |
| `src/test-helpers/venus/VRTVaultHarness.sol` | `../../VRTVault/VRTVault.sol` |
| `src/test-helpers/venus/XVSVestingHarness.sol` | `../../Tokens/XVS/XVSVesting.sol` |

### 5.2 Hardhat Test Patches (TypeScript)
Endure maintains 26 specific string rewrites across 12 Hardhat test files to support the `AccessControlManagerMock` FQN resolution. These patches ensure that `hardhat-deploy` and `smock` can locate vendored test mocks without requiring `module-alias` hacks.

## 6. lib/ Packages (External Dependencies)
The following 5 `@venusprotocol/*` packages are vendored byte-identical under `lib/venusprotocol-*/`.

| Package | Version | Git repo | Commit SHA |
|---------|---------|----------|------------|
| `lib/venusprotocol-governance-contracts/` | `2.13.0` | `VenusProtocol/governance-contracts` | `f8d3efe9578c8cd11330181bb4396f6b449e654c` |
| `lib/venusprotocol-oracle/` | `2.10.0` | `VenusProtocol/oracle` | `c4bd1d95b5989c8f8938812471ab715df77c6b1e` |
| `lib/venusprotocol-protocol-reserve/` | `3.4.0` | `VenusProtocol/protocol-reserve` | `80c53be90a70d9d4704efa33876dc77c0f48f8b2` |
| `lib/venusprotocol-solidity-utilities/` | `2.1.0` | `VenusProtocol/solidity-utilities` | `d891bec6e60338132994560b9d47f2865ee33e0d` |
| `lib/venusprotocol-token-bridge/` | `2.7.0` | `VenusProtocol/token-bridge` | `845a6fa27a0fde98ce6ad621f2340b247d23c866` |

## 7. Toolchain Divergence
Endure deliberately diverges from the Venus toolchain to maintain a leaner dependency profile and avoid global remappings that obscure contract provenance.

### 7.1 Dependency Versions
| Tool | Venus Version | Endure Version | Impact |
|------|---------------|----------------|--------|
| `hardhat` | `^2.14.0` | `^2.19.0` | None (Backward compatible) |
| `@nomiclabs/hardhat-ethers` | `^2.2.3` | `^2.2.3` | Identical |
| `@defi-wonderland/smock` | `^2.3.4` | `^2.3.0` | Minor API surface differences in spy wrapping |

### 7.2 Behavioral Deviations
- **No `module-alias`**: Venus uses `module-alias` to point `hardhat-ethers` to `hardhat-deploy-ethers`. Endure uses standard peer dependencies. This requires explicit `ethers.getContractFactory` calls in scenarios where Venus relies on implicit aliasing.
- **Typechain Resolution**: Endure resolves Typechain targets from `./typechain-types` directly, whereas Venus often uses remapped `typechain/` paths. This is reflected in the 26 patches documented in §5.2.

## 8. Stance B Audit Posture
To verify byte-identity and audit parity:
1. Identify the file in `src/` (excluding `src/endure/`).
2. Locate the corresponding file in the `VenusProtocol/venus-protocol` repository at commit `6400a067`.
3. Compute the SHA-256 hash of both files.
4. Parity is confirmed if hashes match, or if the deviation is explicitly listed in §5.1.
