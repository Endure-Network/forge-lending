# Upstream: moonwell-contracts-v2

## Source

- **Repository**: https://github.com/moonwell-fi/moonwell-contracts-v2
- **Commit**: `8d5fb1107babf7935cfabc2f6ecdb1722547f085`
- **Clone date**: 2026-04-23

## Configuration Divergences

Endure diverges from upstream defaults to suit single-chain deployment:
- **EVM Version**: `shanghai` (Upstream uses `cancun`).
- **Optimizer**: `enabled = true`, `runs = 200` (Upstream uses `runs = 1`).
- **Invariants**: `runs = 1000`, `depth = 50`.
- **RPC Endpoints**: Removed all external RPC providers from `foundry.toml`.
- **Remappings**: Removed `@wormhole/` and `@proposals/`.

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

