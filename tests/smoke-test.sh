#!/bin/bash
# ── Smoke Test Suite ──────────────────────────────────────────
# Runs after every deployment to verify the app works correctly.
#
# "Smoke test" comes from hardware testing:
# Turn on the device and check if smoke comes out.
# In software: basic checks that catch obvious failures.
#
# These tests run in the CI/CD pipeline.
# If they fail → block the deployment / trigger rollback.

set -e

BASE_URL=${1:-http://localhost:30080}
EXPECTED_VERSION=${2:-""}
EXPECTED_COLOR=${3:-""}

PASS=0
FAIL=0
ERRORS=()

# ── Test helper ───────────────────────────────────────────────
check() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"

  if echo "$actual" | grep -q "$expected" 2>/dev/null; then
    echo "  ✅ $test_name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $test_name"
    echo "     Expected: '$expected'"
    echo "     Got:      '${actual:0:100}'"
    FAIL=$((FAIL + 1))
    ERRORS+=("$test_name")
  fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Smoke Tests: $BASE_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Test 1: Health endpoint ────────────────────────────────────
echo "1. Health & Readiness"
HEALTH=$(curl -sf --max-time 10 "$BASE_URL/health" 2>/dev/null \
  || echo '{"status":"error"}')
check "Health returns healthy" "healthy" "$HEALTH"
check "Redis connected" "connected" "$HEALTH"

READY=$(curl -sf --max-time 10 "$BASE_URL/ready" 2>/dev/null \
  || echo '{"status":"error"}')
check "Ready endpoint returns ready" "ready" "$READY"

# ── Test 2: Version verification ──────────────────────────────
echo ""
echo "2. Version Verification"
VERSION_INFO=$(curl -sf --max-time 10 \
  "$BASE_URL/version" 2>/dev/null \
  || echo '{}')
check "Version endpoint responds" "version" "$VERSION_INFO"

if [ -n "$EXPECTED_VERSION" ]; then
  check "Correct version deployed ($EXPECTED_VERSION)" \
    "$EXPECTED_VERSION" "$VERSION_INFO"
fi

if [ -n "$EXPECTED_COLOR" ]; then
  check "Correct color active ($EXPECTED_COLOR)" \
    "$EXPECTED_COLOR" "$VERSION_INFO"
fi

# ── Test 3: URL shortening ─────────────────────────────────────
echo ""
echo "3. URL Shortening"
SHORTEN=$(curl -sf --max-time 10 \
  -X POST "$BASE_URL/shorten" \
  -H "Content-Type: application/json" \
  -d '{"url":"https://kubernetes.io"}' \
  2>/dev/null || echo '{}')
check "Shorten returns short_code" "short_code" "$SHORTEN"

CODE=$(echo "$SHORTEN" | python3 -c \
  "import sys,json
try:
    print(json.load(sys.stdin).get('short_code',''))
except:
    print('')" 2>/dev/null)

# ── Test 4: Redirect ───────────────────────────────────────────
echo ""
echo "4. Redirect"
if [ -n "$CODE" ]; then
  REDIRECT_STATUS=$(curl -sf --max-time 10 \
    -o /dev/null \
    -w "%{http_code}" \
    "$BASE_URL/r/$CODE" 2>/dev/null || echo "000")
  check "Redirect returns 3xx" "3" "$REDIRECT_STATUS"
else
  echo "  ⚠️  Skipped (no code from previous test)"
fi

# ── Test 5: Stats ──────────────────────────────────────────────
echo ""
echo "5. Stats"
if [ -n "$CODE" ]; then
  STATS=$(curl -sf --max-time 10 \
    "$BASE_URL/stats/$CODE" 2>/dev/null || echo '{}')
  check "Stats returns clicks field" "clicks" "$STATS"
fi

# ── Test 6: 404 handling ───────────────────────────────────────
echo ""
echo "6. Error Handling"
NOT_FOUND=$(curl -sf \
  --max-time 10 \
  -o /dev/null \
  -w "%{http_code}" \
  "$BASE_URL/r/notexist" 2>/dev/null || echo "000")
check "404 for non-existent code" "404" "$NOT_FOUND"

# ── Test 7: Feature flags ─────────────────────────────────────
echo ""
echo "7. Feature Flags"
FLAGS=$(curl -sf --max-time 10 \
  "$BASE_URL/flags" 2>/dev/null || echo '{}')
check "Flags endpoint responds" "flags" "$FLAGS"

# ── Summary ────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS passed | $FAIL failed"
if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "  Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "    - $err"
  done
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Exit non-zero if any test failed
# This causes CI pipelines to fail the step
[ $FAIL -eq 0 ] && exit 0 || exit 1
