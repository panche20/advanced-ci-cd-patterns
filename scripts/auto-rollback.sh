#!/bin/bash
# ── Automated Rollback Monitor ────────────────────────────────
#
# Purpose: Monitor the app after deployment.
#          If error rate exceeds threshold → auto rollback.
#
# This runs in CI/CD pipeline AFTER the deployment switch.
# If deployment causes increased errors → rollback automatically.
# No human intervention needed.
#
# Interview: "How do you ensure a bad deploy doesn't stay live?"
# Answer: Post-deployment monitoring with automated rollback.
#         Monitor for N minutes. If error rate exceeds threshold,
#         switch back to previous deployment automatically.

set -e

BASE_URL="${1:-http://localhost:30080}"
MONITOR_DURATION="${2:-120}"    # seconds to monitor
ERROR_THRESHOLD="${3:-10}"      # % error rate that triggers rollback
NAMESPACE="${4:-url-shortener}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Post-Deployment Monitor"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  URL:       $BASE_URL"
echo "  Duration:  ${MONITOR_DURATION}s"
echo "  Threshold: ${ERROR_THRESHOLD}% error rate"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

TOTAL=0
ERRORS=0
START_TIME=$(date +%s)
END_TIME=$((START_TIME + MONITOR_DURATION))

rollback() {
  local reason="$1"
  echo ""
  echo -e "${RED}━━━ ROLLBACK TRIGGERED ━━━${NC}"
  echo "  Reason: $reason"
  echo ""

  # Determine which color to roll back to
  CURRENT_COLOR=$(kubectl get service url-shortener \
    -n "$NAMESPACE" \
    -o jsonpath='{.spec.selector.color}' 2>/dev/null)

  if [ "$CURRENT_COLOR" = "green" ]; then
    ROLLBACK_COLOR="blue"
  else
    ROLLBACK_COLOR="green"
  fi

  echo "  Switching back to $ROLLBACK_COLOR..."

  kubectl patch service url-shortener \
    -n "$NAMESPACE" \
    -p "{\"spec\": {\"selector\": {\"color\": \"$ROLLBACK_COLOR\"}}}" \
    2>/dev/null

  kubectl patch service url-shortener-external \
    -n "$NAMESPACE" \
    -p "{\"spec\": {\"selector\": {\"color\": \"$ROLLBACK_COLOR\"}}}" \
    2>/dev/null

  echo -e "${GREEN}  ✅ Rolled back to $ROLLBACK_COLOR${NC}"
  echo ""
  exit 1
}

while [ $(date +%s) -lt $END_TIME ]; do
  # Make a health request
  HTTP_STATUS=$(curl -sf \
    --max-time 5 \
    -o /dev/null \
    -w "%{http_code}" \
    "$BASE_URL/health" 2>/dev/null || echo "000")

  TOTAL=$((TOTAL + 1))

  if [ "$HTTP_STATUS" != "200" ]; then
    ERRORS=$((ERRORS + 1))
    echo -e "  ${YELLOW}⚠️  Request $TOTAL: HTTP $HTTP_STATUS${NC}"
  fi

  # Calculate error rate after minimum sample
  if [ $TOTAL -ge 10 ]; then
    ERROR_RATE=$(echo "scale=1; $ERRORS * 100 / $TOTAL" | bc)

    ELAPSED=$(($(date +%s) - START_TIME))
    REMAINING=$((MONITOR_DURATION - ELAPSED))

    # Show progress every 10 requests
    if [ $((TOTAL % 10)) -eq 0 ]; then
      echo "  Check $TOTAL: ${ERRORS}/${TOTAL} errors \
(${ERROR_RATE}%) | ${REMAINING}s remaining"
    fi

    # Check if error rate exceeds threshold
    THRESHOLD_EXCEEDED=$(echo \
      "$ERROR_RATE > $ERROR_THRESHOLD" | bc 2>/dev/null || echo 0)

    if [ "$THRESHOLD_EXCEEDED" = "1" ]; then
      rollback \
        "Error rate ${ERROR_RATE}% exceeds threshold ${ERROR_THRESHOLD}%"
    fi
  fi

  sleep 2
done

# Final assessment
FINAL_ERROR_RATE=0
if [ $TOTAL -gt 0 ]; then
  FINAL_ERROR_RATE=$(echo "scale=2; $ERRORS * 100 / $TOTAL" | bc)
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}✅ Deployment Stable${NC}"
echo "  Total requests: $TOTAL"
echo "  Errors:         $ERRORS"
echo "  Error rate:     ${FINAL_ERROR_RATE}%"
echo "  Threshold:      ${ERROR_THRESHOLD}%"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
exit 0
