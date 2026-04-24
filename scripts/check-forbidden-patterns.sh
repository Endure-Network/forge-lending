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
  "TemporalGovernor"
  "MultichainGovernor"
  "AdminMultisig"
)

# MultiRewardDistributor is kept in src/rewards/ as a Stance B exception:
# ComptrollerStorage.sol (kept core) imports it and cannot be modified.
# We check it separately, excluding the rewards/ directory itself.
MULTI_REWARD_EXCEPTION_DIR="packages/contracts/src/rewards"

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

# Check MultiRewardDistributor outside of the allowed rewards/ directory
if grep -r "MultiRewardDistributor" "$SRC_DIR" --include="*.sol" -l 2>/dev/null | grep -v "^$MULTI_REWARD_EXCEPTION_DIR" | grep -v "^packages/contracts/src/Comptroller" | grep -v "^packages/contracts/src/ComptrollerStorage" | grep -q .; then
  echo "FORBIDDEN PATTERN FOUND: MultiRewardDistributor (outside allowed core files)"
  grep -r "MultiRewardDistributor" "$SRC_DIR" --include="*.sol" -l | grep -v "^$MULTI_REWARD_EXCEPTION_DIR" | grep -v "^packages/contracts/src/Comptroller" | grep -v "^packages/contracts/src/ComptrollerStorage"
  FOUND=1
fi

if [ "$FOUND" -eq 1 ]; then
  echo "ERROR: Forbidden patterns found in packages/contracts/src/"
  exit 1
fi

echo "OK: No forbidden patterns found in packages/contracts/src/"
exit 0
