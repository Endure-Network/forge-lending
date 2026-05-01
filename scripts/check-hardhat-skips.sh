#!/usr/bin/env bash
set -euo pipefail

# check-hardhat-skips.sh — Drift detector between hardhat.config.ts exclusion
# arrays and the SKIPPED.md documentation file.
#
# Exits 0 if the two sources agree, 1 if they diverge.

REPO_ROOT="$(git rev-parse --show-toplevel)"
CONFIG="$REPO_ROOT/packages/contracts/hardhat.config.ts"
SKIPPED="$REPO_ROOT/packages/contracts/tests/hardhat/SKIPPED.md"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

CONFIG_SET="$TMP_DIR/config.txt"
SKIPPED_SET="$TMP_DIR/skipped.txt"

echo "hardhat-skips drift check"
echo "========================="
echo ""

# ===== 1. Extract from hardhat.config.ts =====

# EXCLUDED_TEST_DIRS — directory basenames (e.g. "Swap")
config_dirs=$(
  awk '/^const EXCLUDED_TEST_DIRS/,/^];/' "$CONFIG" \
    | grep -oE '"[^"]+"' \
    | tr -d '"' \
    | sort
) || true
dir_count=$(echo "$config_dirs" | grep -c . 2>/dev/null || echo 0)
dir_list=$(echo "$config_dirs" | paste -sd, - 2>/dev/null | sed 's/,/, /g' || true)

# EXCLUDED_TEST_FILES — grep for quoted paths directly (avoids awk range issues with string[])
config_files=$(
  grep -E '^[[:space:]]*"tests/hardhat/' "$CONFIG" \
    | sed -E 's/^[[:space:]]*"([^"]+)".*/\1/' \
    | sort
) || true
file_count=$(echo "$config_files" | grep -c . 2>/dev/null || echo 0)

echo "Config (hardhat.config.ts):"
echo "  EXCLUDED_TEST_DIRS:  $dir_count entries (${dir_list:-none})"
echo "  EXCLUDED_TEST_FILES: $file_count entries"
echo ""

: > "$CONFIG_SET"
if [ -n "$config_files" ]; then
  echo "$config_files" >> "$CONFIG_SET"
fi

if [ -n "$config_dirs" ]; then
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    dir_path="$REPO_ROOT/packages/contracts/tests/hardhat/$d"
    if [ -d "$dir_path" ]; then
      find "$dir_path" -name '*.ts' -type f \
        | sed "s|$REPO_ROOT/packages/contracts/||" \
        >> "$CONFIG_SET"
    fi
  done <<< "$config_dirs"
fi

sort -u -o "$CONFIG_SET" "$CONFIG_SET"
grep -v '^$' "$CONFIG_SET" > "$CONFIG_SET.tmp" 2>/dev/null && mv "$CONFIG_SET.tmp" "$CONFIG_SET" || : > "$CONFIG_SET"

# ===== 2. Extract from SKIPPED.md =====

# Parse table rows: first column, strip backticks, keep only .ts/.js paths.
# Tolerant of both old (plain text) and new (backticked) table formats.
# Header rows are filtered by keyword match.
grep -E '^\|' "$SKIPPED" \
  | grep -Ev '^\|[[:space:]]*-' \
  | grep -Evi '^\|[[:space:]]*(Test file|File[[:space:]]|Status|Count|Parameter|Missing|Wrong)' \
  | sed -E 's/^\|[[:space:]]*//' \
  | sed -E 's/[[:space:]]*\|.*//' \
  | sed -E 's/`//g' \
  | sed -E 's/^[[:space:]]+|[[:space:]]+$//' \
  | grep -E '\.(ts|js)$' \
  | while IFS= read -r f; do
      if [[ "$f" != tests/hardhat/* ]]; then
        echo "tests/hardhat/$f"
      else
        echo "$f"
      fi
    done \
  | sort -u > "$SKIPPED_SET"

skipped_count=$(wc -l < "$SKIPPED_SET" | tr -d ' ')

echo "SKIPPED.md:"
echo "  $skipped_count file entries"
echo ""

# ===== 3. Set comparison =====

has_errors=false

in_config_only=$(comm -23 "$CONFIG_SET" "$SKIPPED_SET" || true)

in_skipped_only_raw=$(comm -13 "$CONFIG_SET" "$SKIPPED_SET" || true)
in_skipped_only=""
if [ -n "$in_skipped_only_raw" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    covered=false
    if [ -n "$config_dirs" ]; then
      while IFS= read -r d; do
        [ -z "$d" ] && continue
        if [[ "$f" == "tests/hardhat/$d/"* ]]; then
          covered=true
          break
        fi
      done <<< "$config_dirs"
    fi
    if ! $covered; then
      in_skipped_only="${in_skipped_only}${f}"$'\n'
    fi
  done <<< "$in_skipped_only_raw"
fi
in_skipped_only=$(echo "$in_skipped_only" | grep -v '^$' || true)

echo "Set comparison:"

if [ -n "$in_config_only" ] || [ -n "$in_skipped_only" ]; then
  has_errors=true
  echo "ERRORS:"
  if [ -n "$in_config_only" ]; then
    while IFS= read -r f; do
      echo "  - In config but not in SKIPPED.md: $f"
    done <<< "$in_config_only"
  fi
  if [ -n "$in_skipped_only" ]; then
    while IFS= read -r f; do
      echo "  - In SKIPPED.md but not in config: $f"
    done <<< "$in_skipped_only"
  fi
else
  echo "  ✓ All config entries are documented"
  echo "  ✓ All documented entries are excluded"
fi

echo ""
if $has_errors; then
  echo "Exit: 1 (drift detected)"
  exit 1
else
  echo "Exit: 0 (no drift)"
  exit 0
fi
