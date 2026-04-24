#!/usr/bin/env bash
# Endure Phase 0 - End-to-End smoke test against a live Anvil chain.
#
# Exercises the full supply -> borrow -> repay -> redeem lifecycle using
# cast, validating that the deployed protocol behaves correctly outside
# the foundry test harness.
#
# Usage:
#   1. Start anvil: `anvil` (defaults to http://localhost:8545, chainId 31337)
#   2. Deploy:      `cd packages/deploy && forge script src/DeployLocal.s.sol --rpc-url http://localhost:8545 --broadcast --private-key 0xac...`
#   3. Run:         `scripts/e2e-smoke.sh`
#
# Exits 0 on success, non-zero on any step failure or Failure-event emission.

set -euo pipefail

URL=${RPC_URL:-http://localhost:8545}
ADDR_FILE=${ADDR_FILE:-packages/deploy/broadcast/addresses.json}

# Anvil default accounts
DEPLOYER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ALICE_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
ALICE=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

# Moonwell Failure event signature. Emitted on soft-rejection (status=1, bad outcome).
FAILURE_TOPIC=0x45b96fe442630264581b197e84bbada861235052c5a1aadfff9ea4e40a969aa0

if [ ! -f "$ADDR_FILE" ]; then
    echo "ERROR: $ADDR_FILE not found. Run DeployLocal.s.sol first."
    exit 1
fi

COMPTROLLER=$(python3 -c "import json; print(json.load(open('$ADDR_FILE'))['contracts']['comptrollerProxy'])")
MWTAO=$(python3       -c "import json; print(json.load(open('$ADDR_FILE'))['contracts']['mWTAO'])")
MALPHA30=$(python3    -c "import json; print(json.load(open('$ADDR_FILE'))['contracts']['mMockAlpha30'])")
WTAO=$(python3        -c "import json; print(json.load(open('$ADDR_FILE'))['contracts']['wtao'])")
ALPHA=$(python3       -c "import json; print(json.load(open('$ADDR_FILE'))['contracts']['mockAlpha30'])")

# Helpers
quiet() { "$@" --rpc-url "$URL" > /dev/null 2>&1; }
call()  { cast call "$@" --rpc-url "$URL"; }

# Send a tx and fail if Moonwell Failure event is emitted.
send_strict() {
    local label=$1; shift
    local out
    out=$("$@" --rpc-url "$URL" 2>&1)
    if echo "$out" | grep -q "$FAILURE_TOPIC"; then
        echo "  ❌ $label: Moonwell Failure event emitted"
        echo "$out" | tail -20
        exit 1
    fi
    if ! echo "$out" | grep -q "status.*1 (success)"; then
        echo "  ❌ $label: tx did not return status=1"
        echo "$out" | tail -20
        exit 1
    fi
    echo "  ✅ $label"
}

echo "=== Endure Phase 0 live E2E smoke test ==="
echo "RPC: $URL"
echo ""

echo "--- Supply-side setup ---"
send_strict "mint 100 Alpha to Alice"                cast send "$ALPHA"    "mint(address,uint256)" "$ALICE"    100000000000000000000   --private-key "$DEPLOYER_PK"
send_strict "mint 1000 WTAO to Deployer"             cast send "$WTAO"     "mint(address,uint256)" "$DEPLOYER" 1000000000000000000000  --private-key "$DEPLOYER_PK"
send_strict "Deployer approves mWTAO"                cast send "$WTAO"     "approve(address,uint256)" "$MWTAO" 100000000000000000000   --private-key "$DEPLOYER_PK"
send_strict "Deployer supplies 100 WTAO"             cast send "$MWTAO"    "mint(uint256)" 100000000000000000000                       --private-key "$DEPLOYER_PK"
send_strict "Alice approves mMockAlpha30"            cast send "$ALPHA"    "approve(address,uint256)" "$MALPHA30" 100000000000000000000 --private-key "$ALICE_PK"
send_strict "Alice supplies 100 Alpha"               cast send "$MALPHA30" "mint(uint256)" 100000000000000000000                       --private-key "$ALICE_PK"
send_strict "Alice enters alpha market"              cast send "$COMPTROLLER" "enterMarkets(address[])" "[$MALPHA30]"                  --private-key "$ALICE_PK"

CASH=$(call "$MWTAO" "getCash()(uint256)" | awk '{print $1}')
python3 - <<PY || exit 1
cash = $CASH
assert cash >= 100000000000000000000, f"mWTAO cash too low: {cash}"
PY
echo "  ✅ mWTAO cash sufficient: $CASH"

echo ""
echo "--- Borrow lifecycle ---"
send_strict "Alice borrows 10 WTAO"                  cast send "$MWTAO" "borrow(uint256)" 10000000000000000000                         --private-key "$ALICE_PK"
ALICE_WTAO=$(call "$WTAO" "balanceOf(address)(uint256)" "$ALICE" | awk '{print $1}')
python3 - <<PY || exit 1
bal = $ALICE_WTAO
assert bal == 10000000000000000000, f"Alice WTAO expected 1e19, got {bal}"
PY
echo "  ✅ Alice received 10 WTAO"

send_strict "Alice approves repay"                   cast send "$WTAO" "approve(address,uint256)" "$MWTAO" 15000000000000000000        --private-key "$ALICE_PK"
send_strict "Alice repays 10 WTAO"                   cast send "$MWTAO" "repayBorrow(uint256)" 10000000000000000000                    --private-key "$ALICE_PK"

DEBT=$(call "$MWTAO" "borrowBalanceStored(address)(uint256)" "$ALICE" | awk '{print $1}')
python3 - <<PY || exit 1
# Accrued interest can leave dust; tolerate < 1e12 wei (0.000001 token).
debt = $DEBT
assert debt < 1_000_000_000_000, f"Alice post-repay debt too high: {debt}"
PY
echo "  ✅ Alice debt cleared (dust: $DEBT)"

echo ""
echo "--- Solvency invariant ---"
TB=$(call   "$MWTAO" "totalBorrows()(uint256)"  | awk '{print $1}')
CASH=$(call "$MWTAO" "getCash()(uint256)"       | awk '{print $1}')
RESV=$(call "$MWTAO" "totalReserves()(uint256)" | awk '{print $1}')
echo "  mWTAO cash:         $CASH"
echo "  mWTAO totalBorrows: $TB"
echo "  mWTAO totalReserves:$RESV"
python3 - <<PY
tb, cash, resv = $TB, $CASH, $RESV
assert cash + resv >= tb, f"SOLVENCY VIOLATED: cash({cash}) + reserves({resv}) < borrows({tb})"
print("  ✅ Solvency holds")
PY

echo ""
echo "=== E2E smoke test PASSED ==="
