#!/usr/bin/env bash
# check-test-mapping.sh
# Enforces that every deleted Phase 0 Endure test has a mapping row in the behavior-mapping table.
# Exit 0 if all deletions covered; exit 1 if any mapping row missing.

set -euo pipefail

CONTRACTS_ROOT="packages/contracts"
MAPPING_DOC="docs/briefs/phase-0.5-venus-rebase-test-mapping.md"

if [ ! -f "$MAPPING_DOC" ]; then
    echo "ERROR: Behavior mapping table not found at $MAPPING_DOC"
    exit 1
fi

PHASE0_TESTS=(
    "test/endure/integration/AliceLifecycle.t.sol"
    "test/endure/integration/Liquidation.t.sol"
    "test/endure/SeedDeposit.t.sol"
    "test/endure/RBACSeparation.t.sol"
    "test/endure/EnduRateModelParams.t.sol"
    "test/endure/MockAlpha.t.sol"
    "test/endure/WTAO.t.sol"
    "test/endure/MockPriceOracle.t.sol"
    "test/endure/invariant/InvariantSolvency.t.sol"
)

MISSING=0
CHECKED=0

for test_path in "${PHASE0_TESTS[@]}"; do
    full_path="$CONTRACTS_ROOT/$test_path"
    if [ ! -f "$full_path" ]; then
        # Test was deleted — check if mapping doc has a row for it
        if grep -q "$test_path" "$MAPPING_DOC"; then
            echo "OK: $test_path has mapping row"
        else
            echo "MISSING MAPPING: $test_path was deleted but has no row in $MAPPING_DOC"
            MISSING=$((MISSING+1))
        fi
    fi
    CHECKED=$((CHECKED+1))
done

if [ "$MISSING" -ne 0 ]; then
    echo ""
    echo "ERROR: $MISSING deleted test(s) lack mapping rows in $MAPPING_DOC"
    echo "Add rows to the mapping table before deleting Phase 0 tests."
    exit 1
fi

echo "OK: All deleted Phase 0 tests have mapping rows ($CHECKED tests checked)"
exit 0
