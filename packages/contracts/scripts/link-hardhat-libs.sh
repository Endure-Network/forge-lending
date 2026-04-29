#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
NM="$PKG_DIR/node_modules"

mkdir -p "$NM/@venusprotocol" "$NM/@openzeppelin"

for pkg in oracle governance-contracts protocol-reserve solidity-utilities token-bridge; do
  target="$PKG_DIR/lib/venusprotocol-${pkg}"
  link="$NM/@venusprotocol/${pkg}"
  [ -L "$link" ] && rm "$link"
  [ -d "$target" ] && ln -s "../../lib/venusprotocol-${pkg}" "$link"
done

for oz in contracts contracts-upgradeable; do
  target="$PKG_DIR/lib/openzeppelin-${oz}/contracts"
  link="$NM/@openzeppelin/${oz}"
  [ -L "$link" ] && rm "$link"
  [ -d "$target" ] && ln -s "../../lib/openzeppelin-${oz}/contracts" "$link"
done
