#!/usr/bin/env bash
# check-test-mapping.sh
# Enforces that every deleted .t.sol test (vs main) has a mapping row in the behavior-mapping table.
# Exit 0 if all deletions covered; exit 1 if any mapping row missing.

set -euo pipefail

MAPPING_DOC="docs/briefs/phase-0.5-venus-rebase-test-mapping.md"

if [ ! -f "$MAPPING_DOC" ]; then
    echo "ERROR: Behavior mapping table not found at $MAPPING_DOC"
    exit 1
fi

# Dynamically discover deleted .t.sol files between main and HEAD
DELETED_TESTS=$(git diff --diff-filter=D --name-only main..HEAD -- '*.t.sol' | grep -E '\.t\.sol$' || true)

if [ -z "$DELETED_TESTS" ]; then
    echo "OK: No deleted .t.sol files found between main and HEAD"
    exit 0
fi

exit_code=0
CHECKED=0

while IFS= read -r test_file; do
    [ -z "$test_file" ] && continue
    basename_sol=$(basename "$test_file")
    if grep -q "$basename_sol" "$MAPPING_DOC"; then
        echo "OK: $test_file has mapping row"
    else
        echo "MISSING MAPPING ROW for deleted test: $test_file"
        exit_code=1
    fi
    CHECKED=$((CHECKED+1))
done <<< "$DELETED_TESTS"

if [ "$exit_code" -ne 0 ]; then
    echo ""
    echo "ERROR: One or more deleted tests lack mapping rows in $MAPPING_DOC"
    echo "Add rows to the mapping table before deleting tests."
    exit 1
fi

echo "OK: All deleted tests have mapping rows ($CHECKED tests checked)"
exit 0
