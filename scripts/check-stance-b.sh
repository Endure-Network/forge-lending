#!/usr/bin/env bash
# check-stance-b.sh — Stance B byte-identical audit
#
# Purpose:
#   Verifies that vendored content under packages/contracts/ is byte-identical
#   to the corresponding files in the upstream VenusProtocol/venus-protocol
#   repository at the pinned commit recorded in packages/contracts/.upstream-sha.
#
# Audit scope:
#   1. Production Solidity  (src/** excl. src/endure/ and src/test-helpers/venus/)
#   2. Test infrastructure  (src/test-helpers/venus/** → upstream contracts/test/**)
#   3. Helpers + scripts    (helpers/** and script/** → upstream same-relative paths)
#   4. lib/ version manifest (lib/venusprotocol-* consistency with FORK_MANIFEST.md §6)
#
# Exit codes:
#   0 — All vendored files are byte-identical (or have documented deviations)
#   1 — One or more UNDOCUMENTED Stance B violations detected
#
# Usage:
#   bash scripts/check-stance-b.sh
#   (Run from the repository root)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL="${REPO_ROOT}/packages/contracts"
UPSTREAM_DIR="/tmp/upstream"

UPSTREAM_SHA="$(cat "${LOCAL}/.upstream-sha")"

if [ ! -d "${UPSTREAM_DIR}/.git" ]; then
  git clone --filter=blob:none https://github.com/VenusProtocol/venus-protocol.git "${UPSTREAM_DIR}"
fi
git -C "${UPSTREAM_DIR}" checkout "${UPSTREAM_SHA}"

# DOCUMENTED files are exempt from byte-identity (Semantic A).
# Any divergence in a documented file is tolerated without checking the
# specific patch content. Future hardening could pin to expected patch
# hashes to detect drift on top of documented patches.
DOCUMENTED_DEVIATIONS=(
  # §5 import-path patches (VRT/XVS harnesses → venus-staging)
  "src/test-helpers/venus/VRTConverterHarness.sol"
  "src/test-helpers/venus/VRTVaultHarness.sol"
  "src/test-helpers/venus/XVSVestingHarness.sol"
  # §4 import-path patches (../X → ../../X due to test/ → src/test-helpers/venus/ relocation)
  "src/test-helpers/venus/BEP20.sol"
  "src/test-helpers/venus/BadFlashLoanReceiver.sol"
  "src/test-helpers/venus/BorrowDebtFlashLoanReceiver.sol"
  "src/test-helpers/venus/ComptrollerHarness.sol"
  "src/test-helpers/venus/ComptrollerMock.sol"
  "src/test-helpers/venus/ComptrollerMockR1.sol"
  "src/test-helpers/venus/DiamondHarness.sol"
  "src/test-helpers/venus/EvilXDelegator.sol"
  "src/test-helpers/venus/EvilXToken.sol"
  "src/test-helpers/venus/Fauceteer.sol"
  "src/test-helpers/venus/FixedPriceOracle.sol"
  "src/test-helpers/venus/FlashLoanReceiverBase.sol"
  "src/test-helpers/venus/InsufficientRepaymentFlashLoanReceiver.sol"
  "src/test-helpers/venus/InterestRateModelHarness.sol"
  "src/test-helpers/venus/LiquidatorHarness.sol"
  "src/test-helpers/venus/MockDeflationaryToken.sol"
  "src/test-helpers/venus/MockFlashLoanReceiver.sol"
  "src/test-helpers/venus/MockVBNB.sol"
  "src/test-helpers/venus/PrimeScenario.sol"
  "src/test-helpers/venus/SimplePriceOracle.sol"
  "src/test-helpers/venus/VAIControllerHarness.sol"
  "src/test-helpers/venus/VAIHarness.sol"
  "src/test-helpers/venus/VBep20Harness.sol"
  "src/test-helpers/venus/VBep20MockDelegate.sol"
  "src/test-helpers/venus/XVSHarness.sol"
  "src/test-helpers/venus/XVSVaultScenario.sol"
)

is_documented() {
  local f="$1"
  for d in "${DOCUMENTED_DEVIATIONS[@]}"; do
    [ "$f" = "$d" ] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Section 1: Production Solidity (src/** excl. endure/ and test-helpers/venus/)
# ---------------------------------------------------------------------------
PROD_DIVERGED=0
PROD_MATCH=0
PROD_DOCUMENTED=0

while IFS= read -r f; do
  REL="${f#${LOCAL}/}"
  if [[ "$REL" == src/endure/* ]]; then continue; fi
  if [[ "$REL" == src/test-helpers/venus/* ]]; then continue; fi
  if [[ "$REL" == src/* ]]; then
    UPSTREAM_REL="contracts/${REL#src/}"
  else
    continue
  fi
  if [ -f "${UPSTREAM_DIR}/${UPSTREAM_REL}" ]; then
    UP=$(sha256sum "${UPSTREAM_DIR}/${UPSTREAM_REL}" | awk '{print $1}')
    LO=$(sha256sum "$f" | awk '{print $1}')
    if [ "$UP" = "$LO" ]; then
      PROD_MATCH=$((PROD_MATCH+1))
    elif is_documented "$REL"; then
      PROD_DOCUMENTED=$((PROD_DOCUMENTED+1))
      echo "::warning file=${REL}::documented Stance B deviation (see FORK_MANIFEST.md §5)"
    else
      PROD_DIVERGED=$((PROD_DIVERGED+1))
      echo "::error file=${REL}::UNDOCUMENTED Stance B violation (production) - add to FORK_MANIFEST.md or revert"
    fi
  fi
done < <(find "${LOCAL}/src" -name "*.sol" -type f | sort)

# ---------------------------------------------------------------------------
# Section 2: Test infrastructure (src/test-helpers/venus/** → contracts/test/**)
# ---------------------------------------------------------------------------
TEST_DIVERGED=0
TEST_MATCH=0
TEST_DOCUMENTED=0

while IFS= read -r f; do
  REL="${f#${LOCAL}/}"
  # Map src/test-helpers/venus/<path> → contracts/test/<path>
  VENUS_REL="${REL#src/test-helpers/venus/}"
  UPSTREAM_REL="contracts/test/${VENUS_REL}"
  if [ -f "${UPSTREAM_DIR}/${UPSTREAM_REL}" ]; then
    UP=$(sha256sum "${UPSTREAM_DIR}/${UPSTREAM_REL}" | awk '{print $1}')
    LO=$(sha256sum "$f" | awk '{print $1}')
    if [ "$UP" = "$LO" ]; then
      TEST_MATCH=$((TEST_MATCH+1))
    elif is_documented "$REL"; then
      TEST_DOCUMENTED=$((TEST_DOCUMENTED+1))
      echo "::warning file=${REL}::documented test-helper deviation (see FORK_MANIFEST.md §5)"
    else
      TEST_DIVERGED=$((TEST_DIVERGED+1))
      echo "::error file=${REL}::UNDOCUMENTED test-helper divergence"
    fi
  else
    echo "::notice file=${REL}::no upstream match at ${UPSTREAM_REL} (may be Endure-authored)"
  fi
done < <(find "${LOCAL}/src/test-helpers/venus" -name "*.sol" -type f | sort)

# ---------------------------------------------------------------------------
# Section 3: Helpers + scripts (helpers/** and script/** → upstream same paths)
# No documented deviations expected — all are byte-identical.
# ---------------------------------------------------------------------------
TS_DIVERGED=0
TS_MATCH=0

for DIR in helpers script; do
  if [ ! -d "${LOCAL}/${DIR}" ]; then continue; fi
  while IFS= read -r f; do
    REL="${f#${LOCAL}/}"
    UPSTREAM_REL="${REL}"
    if [ -f "${UPSTREAM_DIR}/${UPSTREAM_REL}" ]; then
      UP=$(sha256sum "${UPSTREAM_DIR}/${UPSTREAM_REL}" | awk '{print $1}')
      LO=$(sha256sum "$f" | awk '{print $1}')
      if [ "$UP" = "$LO" ]; then
        TS_MATCH=$((TS_MATCH+1))
      else
        TS_DIVERGED=$((TS_DIVERGED+1))
        echo "::error file=${REL}::UNDOCUMENTED ${DIR}/ divergence"
      fi
    else
      echo "::notice file=${REL}::no upstream match (may be Endure-authored)"
    fi
  done < <(find "${LOCAL}/${DIR}" -name "*.ts" -type f | sort)
done

# ---------------------------------------------------------------------------
# Section 4: lib/ version manifest (directory consistency with FORK_MANIFEST §6)
#
# Vendored lib packages are checked out from specific git commits where
# package.json version is typically "0.0.0" (dev). Per-file sha256 against
# published packages is beyond scope. We verify structural consistency:
# each manifest entry has a directory, each directory has a manifest entry,
# and package names match.
# ---------------------------------------------------------------------------
LIB_CONSISTENT=0
LIB_DIVERGED=0

MANIFEST="${LOCAL}/FORK_MANIFEST.md"
MANIFEST_SLUGS=()

# Parse expected lib packages from FORK_MANIFEST §6 table rows
# Format: | `lib/venusprotocol-<name>/` | `<version>` | ... |
while IFS= read -r line; do
  slug=$(echo "$line" | sed -n 's/.*`lib\/\(venusprotocol-[a-z-]*\)\/.*/\1/p')
  if [ -n "$slug" ]; then
    MANIFEST_SLUGS+=("$slug")
  fi
done < "$MANIFEST"

# Check each manifest entry has a directory with matching package name
if [ ${#MANIFEST_SLUGS[@]} -gt 0 ]; then
  for slug in "${MANIFEST_SLUGS[@]}"; do
    LIB_DIR="${LOCAL}/lib/${slug}"
    if [ -d "$LIB_DIR" ]; then
      PKG_JSON="${LIB_DIR}/package.json"
      if [ -f "$PKG_JSON" ]; then
        PKG_SUFFIX="${slug#venusprotocol-}"
        EXPECTED_NAME="@venusprotocol/${PKG_SUFFIX}"
        ACTUAL_NAME=$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PKG_JSON" | head -1)
        if [ "$ACTUAL_NAME" = "$EXPECTED_NAME" ]; then
          LIB_CONSISTENT=$((LIB_CONSISTENT+1))
        else
          LIB_DIVERGED=$((LIB_DIVERGED+1))
          echo "::error file=lib/${slug}/package.json::package name mismatch: expected ${EXPECTED_NAME}, got ${ACTUAL_NAME}"
        fi
      else
        LIB_DIVERGED=$((LIB_DIVERGED+1))
        echo "::error file=lib/${slug}::missing package.json"
      fi
    else
      LIB_DIVERGED=$((LIB_DIVERGED+1))
      echo "::error::lib/${slug} listed in FORK_MANIFEST.md §6 but directory missing"
    fi
  done
else
  echo "::error::No lib packages found in FORK_MANIFEST.md §6"
  LIB_DIVERGED=$((LIB_DIVERGED+1))
fi

# Check for unexpected lib/venusprotocol-* directories not in manifest
for d in "${LOCAL}"/lib/venusprotocol-*/; do
  [ -d "$d" ] || continue
  slug=$(basename "$d")
  found=0
  for m in "${MANIFEST_SLUGS[@]}"; do
    if [ "$m" = "$slug" ]; then found=1; break; fi
  done
  if [ "$found" -eq 0 ]; then
    LIB_DIVERGED=$((LIB_DIVERGED+1))
    echo "::error::lib/${slug} exists on disk but not listed in FORK_MANIFEST.md §6"
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL_DIVERGED=$((PROD_DIVERGED + TEST_DIVERGED + TS_DIVERGED + LIB_DIVERGED))

echo ""
echo "Stance B audit summary:"
echo "  Production Solidity:    byte-identical=${PROD_MATCH} documented=${PROD_DOCUMENTED} diverged=${PROD_DIVERGED}"
echo "  Test infrastructure:    byte-identical=${TEST_MATCH} documented=${TEST_DOCUMENTED} diverged=${TEST_DIVERGED}"
echo "  Helpers + scripts:      byte-identical=${TS_MATCH} documented=0 diverged=${TS_DIVERGED}"
echo "  lib/ version manifest:  consistent=${LIB_CONSISTENT} diverged=${LIB_DIVERGED}"
echo ""
echo "Total undocumented divergences: ${TOTAL_DIVERGED}"

if [ "${TOTAL_DIVERGED}" -ne 0 ]; then exit 1; fi
