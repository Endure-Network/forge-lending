#!/usr/bin/env bash
# Gas snapshot regression check.
#
# Pattern matches 1inch's production CI (1inch/aqua, 1inch/swap-vm):
# tolerance + targeted fuzz-test exclusion. Foundry maintainers have
# partially fixed cross-platform fuzz-gas determinism three times
# (foundry-rs/foundry PRs #7951, #10402; issue #10443 remains open for
# array params) and still recommend --tolerance or explicit exclusion.
#
# Excludes:
#   - Invariant contracts: snapshot entry is revert-count, not gas.
#   - testSettingCF: upstream Moonwell fuzz test whose median-case gas
#     diverges ~40% between macOS ARM64 and Linux x64. Cannot modify
#     upstream file (Stance B discipline), so exclude from snapshot.
# Tolerates:
#   - 5% drift on remaining entries to absorb residual fuzz-gas variance.
#     Real regressions typically exceed 10%.
set -euo pipefail
cd "$(dirname "$0")/../packages/contracts"
forge snapshot --check --tolerance 5 \
  --no-match-contract "Invariant" \
  --no-match-test "testSettingCF"
echo "Gas snapshot check passed (tolerance: 5%, invariants + testSettingCF excluded)"
