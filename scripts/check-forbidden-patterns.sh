#!/usr/bin/env bash
# check-forbidden-patterns.sh
# Scans packages/contracts/src/ for Moonwell remnants that should not exist
# post-Venus-rebase, plus legacy stripped-contract identifiers.
set -euo pipefail

SRC_DIR="packages/contracts/src"

if [ ! -d "$SRC_DIR" ]; then
  echo "No src directory found at $SRC_DIR — skipping check (pre-fork)"
  exit 0
fi

# Moonwell remnants (post-Venus rebase these must not appear)
MOONWELL_PATTERNS=(
  "MToken"
  "MErc20"
  "MErc20Delegator"
  "mWell"
  "WELL"
  "xWELL"
)

# Legacy stripped-contract identifiers
LEGACY_PATTERNS=(
  "0x805"
  "IStakingV2"
  "BittensorStakeAdapter"
  "MAlpha"
  "EnduOracle"
  "@wormhole/"
  "stkWell"
  "TemporalGovernor"
  "MultichainGovernor"
  "AdminMultisig"
)

FOUND=0

for pattern in "${MOONWELL_PATTERNS[@]}"; do
  # Search in src/ excluding FORK_MANIFEST (endure/ is intentionally included)
  matches=$(grep -r "$pattern" "$SRC_DIR" \
    --include="*.sol" \
    -l 2>/dev/null | grep -v FORK_MANIFEST || true)
  if [ -n "$matches" ]; then
    echo "FORBIDDEN MOONWELL REMNANT '$pattern' found in:"
    echo "$matches"
    FOUND=$((FOUND+1))
  fi
done

for pattern in "${LEGACY_PATTERNS[@]}"; do
  if grep -r "$pattern" "$SRC_DIR" --include="*.sol" -l 2>/dev/null | grep -q .; then
    echo "FORBIDDEN LEGACY PATTERN '$pattern' found in:"
    grep -r "$pattern" "$SRC_DIR" --include="*.sol" -l
    FOUND=$((FOUND+1))
  fi
done

if [ "$FOUND" -ne 0 ]; then
  echo "ERROR: $FOUND forbidden pattern(s) found in $SRC_DIR"
  exit 1
fi

echo "OK: No forbidden patterns found in $SRC_DIR"
exit 0
