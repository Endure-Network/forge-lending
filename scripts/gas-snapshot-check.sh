#!/usr/bin/env bash
# Gas snapshot regression check.
#
# Excludes:
#   - Invariant contracts: snapshot entry is revert-count (not gas) and
#     varies across runs/seeds.
#   - testSettingCF: fuzz test whose median-case gas diverges ~40% across
#     CPU architectures because fuzz input selection differs on Linux x64
#     vs macOS ARM64 even with pinned seed. Mean stays within tolerance
#     but median does not; rather than raise tolerance to 50%+ (defeats
#     the check), drop this one entry entirely.
# Tolerates:
#   - 5% drift on remaining entries to absorb residual fuzz-gas variance.
#     Real regressions typically exceed 10%.
set -euo pipefail
cd "$(dirname "$0")/../packages/contracts"
forge snapshot --check --tolerance 5 \
  --no-match-contract "Invariant" \
  --no-match-test "testSettingCF"
echo "Gas snapshot check passed (tolerance: 5%, invariants + testSettingCF excluded)"
