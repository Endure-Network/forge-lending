#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../packages/contracts"
forge snapshot --check
echo "Gas snapshot check passed"
