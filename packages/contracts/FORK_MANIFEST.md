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
The following TypeScript helpers were vendored from Venus `6400a067` into `packages/contracts/` to support the dual-toolchain test suite and deploy pipeline. All are byte-identical to upstream (sha256-verified):

| Endure path | Upstream path |
|---|---|
| `helpers/chains.ts` | `helpers/chains.ts` |
| `helpers/deploymentConfig.ts` | `helpers/deploymentConfig.ts` |
| `helpers/utils.ts` | `helpers/utils.ts` |
| `helpers/markets/types.ts` | `helpers/markets/types.ts` |
| `helpers/markets/index.ts` | `helpers/markets/index.ts` |
| `helpers/markets/hardhat.ts` | `helpers/markets/hardhat.ts` |
| `helpers/markets/bscmainnet.ts` | `helpers/markets/bscmainnet.ts` |
| `helpers/markets/bsctestnet.ts` | `helpers/markets/bsctestnet.ts` |
| `helpers/tokens/index.ts` | `helpers/tokens/index.ts` |
| `helpers/tokens/types.ts` | `helpers/tokens/types.ts` |
| `helpers/tokens/hardhat.ts` | `helpers/tokens/hardhat.ts` |
| `helpers/tokens/bscmainnet.ts` | `helpers/tokens/bscmainnet.ts` |
| `helpers/tokens/bsctestnet.ts` | `helpers/tokens/bsctestnet.ts` |
| `helpers/tokens/common/indexBySymbol.ts` | `helpers/tokens/common/indexBySymbol.ts` |
| `helpers/rateModelHelpers.ts` | `helpers/rateModelHelpers.ts` |
| `helpers/writeFile.ts` | `helpers/writeFile.ts` |
| `script/deploy/comptroller/diamond.ts` | `script/deploy/comptroller/diamond.ts` |

The `helpers/markets/{bscmainnet,bsctestnet}.ts` and `helpers/tokens/{bscmainnet,bsctestnet}.ts` files contain BSC-specific configurations that Endure does not deploy; they are vendored for byte-identity, not for use.

### 4.3 Hardhat-deploy chain (intentionally not auto-run)
The vendored Venus deploy scripts at `packages/contracts/deploy/*.ts` are byte-identical Venus content. By default, the `hardhat-deploy` plugin runs them automatically when `pnpm hardhat node` starts. Under Endure's vendoring scope, this auto-run is **disabled** (see §7) because the vendored deploy chain has 3 distinct module-load gaps:

1. **`deploy/005-deploy-VTreasuryV8.ts` and `deploy/009-configure-vaults.ts`** import 14 chain-specific JSONs from `@venusprotocol/governance-contracts/deployments/`. Endure's vendored `governance-contracts` package (see §6) ships only the `contracts/` subtree of the upstream npm package; the `deployments/` subtree (~1.9 MB of address registries for chains Endure does not deploy on) is not vendored.
2. **`deploy/006-deploy-psm.ts`** imports `@venusprotocol/oracle/dist/deploy/1-deploy-oracles`. The upstream npm package ships compiled `dist/` content; the GitHub source repo (the only source we can pin to via SHA for Stance B) does not contain `dist/`. Vendoring the source `deploy/1-deploy-oracles.ts` would require its transitive imports (`oracle/helpers/deploymentConfig.ts`, ~47 KB) which itself imports `@venusprotocol/venus-protocol/deployments/{bscmainnet,bsctestnet}.json` (~10 MB of upstream production registries — meta-vendoring the chassis itself, since Endure IS the venus-protocol fork).
3. **`deploy/007-deploy-VBNBAdmin.ts`** imports `@venusprotocol/protocol-reserve/dist/deploy/000-psr` with a similar (smaller) cascade.

The total transitive surface to make Venus's deploy chain runnable on a fresh `hardhat` node is at least ~12 MB of upstream production state, much of it unrelated to Endure's audited surface. We declined this scope as misaligned with Endure's goals (we do not deploy on those chains, and the value is evidence-only — the canonical local-deploy path is `EndureDeployHelper`-based, see below).

**Endure's local Hardhat deploy path** (canonical for Hardhat-side dev work, frontend integration):
```
pnpm hardhat node                                                            # one terminal
cd packages/contracts && pnpm hardhat run scripts/deploy-local.ts --network localhost
cd packages/contracts && pnpm hardhat run scripts/smoke-local.ts  --network localhost
```

**Foundry deploy path** (canonical for Foundry-side dev work, lives in `packages/deploy/`):
```
anvil --silent --disable-code-size-limit --gas-limit 1000000000 &
cd packages/deploy && forge script src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast --slow --legacy --code-size-limit 999999
bash scripts/e2e-smoke.sh
```

Both paths produce `packages/deploy/addresses.json` with the same 16-key alphabetized schema and exercise the same `EndureDeployHelper.deployAll()` Solidity logic (the helper lives at `src/endure/EndureDeployHelper.sol` and is the single source of truth for the Endure chassis deploy). Downstream tooling (frontend, integration tests, keepers) is toolchain-agnostic.

Note: `scripts/e2e-smoke.sh` is foundry-tool-based (uses `cast`) and targets Anvil. Running it against `hardhat node` fails on `cast`-vs-Hardhat-EDR JSON-RPC strictness (cast 1.2.2 sends both `input` and `data` fields, which Hardhat 2.28+ rejects per spec). The Hardhat-native `scripts/smoke-local.ts` covers the same supply/borrow/repay/redeem/liquidation flow via ethers and is the canonical Hardhat-side smoke.

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
- **`hardhat-deploy` auto-run on `hardhat node` disabled**: Per-network `deploy: []` override in `hardhat.config.ts` for both the in-process `hardhat` network and the `localhost` network, suppressing the plugin's default behavior of executing every script in `deploy/` on node startup. The vendored Venus `deploy/*.ts` chain has 3 module-load gaps under Endure's vendoring scope (see §4.3); vendoring upstream's full transitive surface (~12 MB of production state) was rejected as scope-misaligned. Endure provides `packages/contracts/scripts/deploy-local.ts` as the on-demand replacement. No vendored Venus content was modified.

## 8. Stance B Audit Posture
To verify byte-identity and audit parity:
1. Identify the file in `src/` (excluding `src/endure/`).
2. Locate the corresponding file in the `VenusProtocol/venus-protocol` repository at commit `6400a067`.
3. Compute the SHA-256 hash of both files.
4. Parity is confirmed if hashes match, or if the deviation is explicitly listed in §5.1.
