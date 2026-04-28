# Upstream

## Status

This repository is in a **dual-vendor intermediate state** during the Phase 0.5
Venus rebase (Stage A complete, Stage B pending). Both Moonwell v2 and Venus
Core Pool source trees are vendored byte-identical and live side-by-side under
`packages/contracts/src/`. Stage B will delete the Moonwell tree in its final
cleanup commits and the Venus tree (currently at `src/venus-staging/`) will
move to `src/`. See `docs/briefs/phase-0.5-venus-rebase-spec.md` for the
full plan.

## Primary upstream (Phase 0, currently live deployable surface)

### Source

- **Repository**: https://github.com/moonwell-fi/moonwell-contracts-v2
- **Commit**: `8d5fb1107babf7935cfabc2f6ecdb1722547f085`
- **Clone date**: 2026-04-23

## Secondary upstream (Phase 0.5 staged, NOT yet on deployed surface)

### Source

- **Repository**: https://github.com/VenusProtocol/venus-protocol
- **Commit**: `6400a067114a101bd3bebfca2a4bd06480e84831`
- **Reference tag**: `v10.2.0-dev.5`
- **Vendored on**: 2026-04-28
- **Vendored under**: `packages/contracts/src/venus-staging/`

### Rationale

- `v10.2.0-dev.5` is functionally identical to `v10.2.0-dev.4` for our
  contracts — `git diff v10.2.0-dev.4 v10.2.0-dev.5 -- contracts/` is empty
  (the bump was audit PDFs only).
- Both tags include the March 20, 2026 donation-attack patch merge (PR #664)
  audited by Quantstamp, Certik, and Hashdit.
- Older `v10.1.0` predates that fix and is not acceptable.
- Endure's tightened Stage A spike at `test/endure/venus/VenusDirectLiquidationSpike.t.sol`
  validates 8/8 hard gates from the spec against this exact pin.

### Venus external dependency packages

Each is vendored byte-identical under `lib/venusprotocol-*/`. Pinned versions
match Venus's own package.json at the pinned commit. See each
`lib/venusprotocol-*/VENDOR.md` for details.

| Package | Version |
|---------|---------|
| `@venusprotocol/governance-contracts` | `2.13.0` |
| `@venusprotocol/oracle` | `2.10.0` |
| `@venusprotocol/protocol-reserve` | `3.4.0` |
| `@venusprotocol/solidity-utilities` | `2.1.0` |
| `@venusprotocol/token-bridge` | `2.7.0` |

## Configuration Divergences

Endure diverges from upstream defaults to suit single-chain deployment:
- **Compiler dispatch**: `auto_detect_solc = true` (Stage A scaffolding;
  reverts to pinned `solc_version = "0.8.25"` once Moonwell is deleted in
  Stage B Chunk 5b). Required because Phase 0 vendored Moonwell pins
  `pragma 0.8.19` and Phase 0.5 vendored Venus pins `pragma 0.8.25` (with
  some legacy 0.5.16); both must compile during the rebase.
- **EVM Version**: `cancun` (Phase 0 used `shanghai`; bumped 2026-04-28 for
  Venus 0.8.25 contracts. Moonwell 0.8.19 contracts are forward-compatible).
- **Optimizer**: `enabled = true`, `runs = 200` (Moonwell uses `runs = 1`).
- **Invariants**: `runs = 1000`, `depth = 50`.
- **RPC Endpoints**: Removed all external RPC providers from `foundry.toml`.
- **Remappings**: Removed `@wormhole/` and `@proposals/`. Added 5
  `@venusprotocol/*` remappings (see `remappings.txt`).
- **OpenZeppelin remappings**: Distinct paths for `@openzeppelin/contracts/`
  and `@openzeppelin/contracts-upgradeable/` (Solidity longest-prefix-wins)
  to satisfy both Moonwell (`@openzeppelin-contracts/...` style) and Venus
  (`@openzeppelin/...` style) imports without ambiguity.

## Vendored Dependencies

All dependencies are vendored flat into `lib/` with `.git` metadata stripped.

| Library | Pinned SHA |
|---------|-----------|
| `forge-std` | `52715a217dc51d0de15877878ab8213f6cbbbab5` |
| `openzeppelin-contracts` | `e50c24f5839db17f46991478384bfda14acfb830` |
| `openzeppelin-contracts-upgradeable` | `3d4c0d5741b131c231e558d7a6213392ab3672a5` |
| `solmate` | `fadb2e2778adbf01c80275bfb99e5c14969d964b` |
| `wormhole` | `aa22a2b950fbbd10221c25a7e19e82e7fd688ed8` |
| `zelt` | `447e7ab0eccfc1b6614714e3c63b8fdefae98076` |

## Strip Manifest

The following upstream modules were removed:
- Governance (TemporalGovernor, multichain logic)
- Well Token (WELL, xWELL, Staking)
- Rewards (MultiRewardDistributor - implementation stripped, storage retained)
- Morpho integrations
- Token Sale / Vesting
- Views (MoonwellViewsV2, MoonwellViewsV3)

## Additions by Endure

Located in `src/endure/`:
- `MockAlpha30.sol`, `MockAlpha64.sol`
- `WTAO.sol`
- `MockPriceOracle.sol`
- `EndureRoles.sol`
- `EnduRateModelParams.sol`

## Synchronization and Backports

### Sync Process
Endure tracks a fixed commit of Moonwell v2. Periodic synchronization involves:
1. Identifying upstream changes since the pinned commit.
2. Applying relevant security fixes or core logic improvements via manual patches.
3. Updating the pinned commit in this file.

### Backport Policy
Upstream changes to core lending logic (Comptroller, MToken, IRM) are prioritized for backporting. Governance and Reward changes are generally ignored as Endure maintains a simplified architecture.

