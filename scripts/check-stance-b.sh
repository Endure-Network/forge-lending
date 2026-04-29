#!/usr/bin/env bash
# check-stance-b.sh — Stance B byte-identical audit
#
# Purpose:
#   Verifies that every vendored Solidity file under packages/contracts/src/
#   (excluding src/endure/ and src/test-helpers/venus/) is byte-identical to
#   the corresponding file in the upstream VenusProtocol/venus-protocol
#   repository at the pinned commit recorded in packages/contracts/.upstream-sha.
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

DOCUMENTED_DEVIATIONS=(
  "src/test-helpers/venus/VRTConverterHarness.sol"
  "src/test-helpers/venus/VRTVaultHarness.sol"
  "src/test-helpers/venus/XVSVestingHarness.sol"
)

is_documented() {
  local f="$1"
  for d in "${DOCUMENTED_DEVIATIONS[@]}"; do
    [ "$f" = "$d" ] && return 0
  done
  return 1
}

DIVERGED=0
MATCH=0
DOCUMENTED=0

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
      MATCH=$((MATCH+1))
    elif is_documented "$REL"; then
      DOCUMENTED=$((DOCUMENTED+1))
      echo "::warning file=${REL}::documented Stance B deviation (see FORK_MANIFEST.md section 6.2)"
    else
      DIVERGED=$((DIVERGED+1))
      echo "::error file=${REL}::UNDOCUMENTED Stance B violation - add to FORK_MANIFEST.md or revert"
    fi
  fi
done < <(find "${LOCAL}/src" -name "*.sol" -type f | sort)

echo "Stance B: byte-identical=${MATCH} documented-deviations=${DOCUMENTED} undocumented-diverged=${DIVERGED}"
if [ "${DIVERGED}" -ne 0 ]; then exit 1; fi
