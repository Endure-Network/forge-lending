# Upstream: moonwell-contracts-v2

## Source

- **Repository**: https://github.com/moonwell-fi/moonwell-contracts-v2
- **Commit**: `8d5fb1107babf7935cfabc2f6ecdb1722547f085`
- **Clone date**: 2026-04-23

## EVM Version Override

The upstream `foundry.toml` targets `cancun`. Endure overrides this to `shanghai` for broader L2 compatibility. See `packages/contracts/foundry.toml` for the active configuration.

## Submodule Pins

| Path | Pinned SHA |
|------|-----------|
| `lib/forge-std` | `52715a217dc51d0de15877878ab8213f6cbbbab5` |
| `lib/openzeppelin-contracts` | `e50c24f5839db17f46991478384bfda14acfb830` |
| `lib/openzeppelin-contracts-upgradeable` | `3d4c0d5741b131c231e558d7a6213392ab3672a5` |
| `lib/solmate` | `fadb2e2778adbf01c80275bfb99e5c14969d964b` |
| `lib/wormhole` | `aa22a2b950fbbd10221c25a7e19e82e7fd688ed8` |
| `lib/zelt` | `447e7ab0eccfc1b6614714e3c63b8fdefae98076` |

## Vendored Dependencies

All dependencies are vendored flat into `lib/` with `.git` metadata stripped. No submodule gitlinks remain.

| Library | Pinned SHA |
|---------|-----------|
| `forge-std` | `52715a217dc51d0de15877878ab8213f6cbbbab5` (v1.8.2-2-g52715a2) |
| `openzeppelin-contracts` | `e50c24f5839db17f46991478384bfda14acfb830` (v4.8.0-254-ge50c24f5) |
| `openzeppelin-contracts-upgradeable` | `3d4c0d5741b131c231e558d7a6213392ab3672a5` |
| `solmate` | `fadb2e2778adbf01c80275bfb99e5c14969d964b` (v6-196-gfadb2e2) |
| `wormhole` | `aa22a2b950fbbd10221c25a7e19e82e7fd688ed8` (v2.14.5-1003-gaa22a2b9) |
| `zelt` | `447e7ab0eccfc1b6614714e3c63b8fdefae98076` |

## Divergences

<!-- Placeholder: list Endure-specific patches applied on top of upstream -->

- None yet. This is a clean vendor of the upstream at the pinned commit.
