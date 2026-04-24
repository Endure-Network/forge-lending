#!/usr/bin/env bash
set -euo pipefail

PATTERNS=(
  "0x805"
  "IStakingV2"
  "BittensorStakeAdapter"
  "MAlpha"
  "EnduOracle"
  "@wormhole/"
  "stkWell"
  "xWELL"
  "MultiRewardDistributor"
  "TemporalGovernor"
  "MultichainGovernor"
  "AdminMultisig"
)

SRC_DIR="packages/contracts/src"

if [ ! -d "$SRC_DIR" ]; then
  echo "No src directory found at $SRC_DIR — skipping check (pre-fork)"
  exit 0
fi

FOUND=0
for pattern in "${PATTERNS[@]}"; do
  if grep -r "$pattern" "$SRC_DIR" --include="*.sol" -l 2>/dev/null | grep -q .; then
    echo "FORBIDDEN PATTERN FOUND: $pattern"
    grep -r "$pattern" "$SRC_DIR" --include="*.sol" -n
    FOUND=1
  fi
done

if [ "$FOUND" -eq 1 ]; then
  echo "ERROR: Forbidden patterns found in packages/contracts/src/"
  exit 1
fi

echo "OK: No forbidden patterns found in packages/contracts/src/"
exit 0
