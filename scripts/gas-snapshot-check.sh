#!/usr/bin/env bash
# Gas snapshot regression check.
#
# Excludes:
#   - Invariant contracts: the snapshot entry is revert-count, not gas;
#     revert counts are seed-sensitive and vary across runs.
# Tolerates:
#   - 5% drift on remaining entries to absorb fuzz-gas variance across
#     CPU architectures (macOS ARM64 vs Linux x64) even with pinned seed.
#     Real regressions typically exceed 10%.
set -euo pipefail
cd "$(dirname "$0")/../packages/contracts"
forge snapshot --check --tolerance 5 --no-match-contract "Invariant"
echo "Gas snapshot check passed (tolerance: 5%, invariants excluded)"
