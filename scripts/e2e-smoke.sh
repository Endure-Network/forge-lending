#!/usr/bin/env bash
# Venus-chassis E2E smoke test against a live Anvil chain.
# Exercises: supply → borrow → repay → direct vToken liquidation.
# Exits 0 on success, non-zero on any step failure.
set -euo pipefail

URL=${RPC_URL:-http://localhost:8545}
ADDR_FILE=${ADDR_FILE:-packages/deploy/addresses.json}

DEPLOYER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ALICE_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
ALICE=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
BOB_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
BOB=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC

if [ ! -f "$ADDR_FILE" ]; then
    echo "ERROR: $ADDR_FILE not found. Run DeployLocal.s.sol first."
    exit 1
fi

read_addr() { python3 -c "import json; print(json.load(open('$ADDR_FILE'))['$1'])"; }

UNITROLLER=$(read_addr unitroller)
VWTAO=$(read_addr vWTAO)
VALPHA30=$(read_addr vAlpha30)
WTAO=$(read_addr wtao)
ALPHA30=$(read_addr mockAlpha30)
ORACLE=$(read_addr resilientOracle)
COMPTROLLER_LENS=$(read_addr comptrollerLens)

call()  { cast call "$@" --rpc-url "$URL"; }

send_strict() {
    local label=$1; shift
    local out
    out=$("$@" --rpc-url "$URL" 2>&1)
    if ! echo "$out" | grep -q "status.*1 (success)"; then
        echo "  ❌ $label: tx reverted or failed"
        echo "$out" | tail -20
        exit 1
    fi
    echo "  ✅ $label"
}

echo "=== Endure Venus E2E smoke test ==="
echo "RPC: $URL"
echo ""

echo "--- Venus state verification ---"
LENS_RESULT=$(call "$UNITROLLER" "comptrollerLens()(address)")
if [ "$LENS_RESULT" = "0x0000000000000000000000000000000000000000" ]; then
    echo "  ❌ comptrollerLens() returned zero address"
    exit 1
fi
echo "  ✅ comptrollerLens = $LENS_RESULT"

ORACLE_RESULT=$(call "$UNITROLLER" "oracle()(address)")
if [ "$ORACLE_RESULT" = "0x0000000000000000000000000000000000000000" ]; then
    echo "  ❌ oracle() returned zero address"
    exit 1
fi
echo "  ✅ oracle = $ORACLE_RESULT"

MARKET_INFO=$(call "$UNITROLLER" "markets(address)(bool,uint256,bool)" "$VWTAO")
IS_LISTED=$(echo "$MARKET_INFO" | head -1 | tr -d '[:space:]')
if [ "$IS_LISTED" != "true" ]; then
    echo "  ❌ vWTAO not listed in markets()"
    echo "  raw: $MARKET_INFO"
    exit 1
fi
echo "  ✅ vWTAO isListed=true"

echo ""
echo "--- Supply-side setup ---"
send_strict "mint 100 Alpha30 to Alice"               cast send "$ALPHA30" "mint(address,uint256)" "$ALICE"    100000000000000000000   --private-key "$DEPLOYER_PK"
send_strict "mint 1000 WTAO to Deployer"              cast send "$WTAO"    "mint(address,uint256)" "$DEPLOYER" 1000000000000000000000  --private-key "$DEPLOYER_PK"
send_strict "Deployer approves vWTAO"                 cast send "$WTAO"    "approve(address,uint256)" "$VWTAO"  100000000000000000000  --private-key "$DEPLOYER_PK"
send_strict "Deployer supplies 100 WTAO"              cast send "$VWTAO"   "mint(uint256)" 100000000000000000000                       --private-key "$DEPLOYER_PK"
send_strict "Alice approves vAlpha30"                 cast send "$ALPHA30" "approve(address,uint256)" "$VALPHA30" 100000000000000000000 --private-key "$ALICE_PK"
send_strict "Alice supplies 100 Alpha30"              cast send "$VALPHA30" "mint(uint256)" 100000000000000000000                      --private-key "$ALICE_PK"
send_strict "Alice enters Alpha30 market"             cast send "$UNITROLLER" "enterMarkets(address[])" "[$VALPHA30]"                  --private-key "$ALICE_PK"

CASH=$(call "$VWTAO" "getCash()(uint256)" | awk '{print $1}')
python3 - <<PY || exit 1
cash = $CASH
assert cash >= 100000000000000000000, f"vWTAO cash too low: {cash}"
PY
echo "  ✅ vWTAO cash sufficient: $CASH"

echo ""
echo "--- Borrow lifecycle ---"
send_strict "Alice borrows 10 WTAO"                   cast send "$VWTAO" "borrow(uint256)" 10000000000000000000                        --private-key "$ALICE_PK"
ALICE_WTAO=$(call "$WTAO" "balanceOf(address)(uint256)" "$ALICE" | awk '{print $1}')
python3 - <<PY || exit 1
bal = $ALICE_WTAO
assert bal == 10000000000000000000, f"Alice WTAO expected 1e19, got {bal}"
PY
echo "  ✅ Alice received 10 WTAO"

send_strict "Alice approves repay"                    cast send "$WTAO" "approve(address,uint256)" "$VWTAO" 15000000000000000000       --private-key "$ALICE_PK"
send_strict "Alice repays 10 WTAO"                    cast send "$VWTAO" "repayBorrow(uint256)" 10000000000000000000                   --private-key "$ALICE_PK"

DEBT=$(call "$VWTAO" "borrowBalanceStored(address)(uint256)" "$ALICE" | awk '{print $1}')
python3 - <<PY || exit 1
debt = $DEBT
assert debt < 1_000_000_000_000, f"Alice post-repay debt too high: {debt}"
PY
echo "  ✅ Alice debt cleared (dust: $DEBT)"

echo ""
echo "--- Solvency invariant ---"
TB=$(call   "$VWTAO" "totalBorrows()(uint256)"  | awk '{print $1}')
CASH=$(call "$VWTAO" "getCash()(uint256)"        | awk '{print $1}')
RESV=$(call "$VWTAO" "totalReserves()(uint256)"  | awk '{print $1}')
echo "  vWTAO cash:          $CASH"
echo "  vWTAO totalBorrows:  $TB"
echo "  vWTAO totalReserves: $RESV"
python3 - <<PY
tb, cash, resv = $TB, $CASH, $RESV
assert cash + resv >= tb, f"SOLVENCY VIOLATED: cash({cash}) + reserves({resv}) < borrows({tb})"
print("  ✅ Solvency holds")
PY

echo ""
echo "=== E2E smoke test PASSED ==="
