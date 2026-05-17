#!/bin/bash
# ── Blue-Green Deployment Script ──────────────────────────────
#
# How blue-green works in this script:
# 1. Determine which color is currently active (blue or green)
# 2. Deploy new version to the INACTIVE color
# 3. Wait for inactive deployment to be healthy
# 4. Run smoke tests against inactive (via test service)
# 5. If tests pass → switch production service to inactive color
# 6. Keep old deployment running for rollback
# 7. After validation → optionally scale down old deployment
#
# Zero downtime: the switch (step 5) is a single API call
# that takes milliseconds.
# Rollback: switch back (single API call, milliseconds)

set -e

# ── Configuration ──────────────────────────────────────────────
NAMESPACE="url-shortener"
NEW_VERSION="${1:-1.1.0}"
NEW_IMAGE="${2:-url-shortener:green}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️  $1${NC}"; }
error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ❌ $1${NC}"; }
heading() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# ── Step 1: Determine Active Color ────────────────────────────
heading "Step 1: Determining Active Color"

ACTIVE_COLOR=$(kubectl get service url-shortener \
  -n "$NAMESPACE" \
  -o jsonpath='{.spec.selector.color}' 2>/dev/null || echo "blue")

if [ "$ACTIVE_COLOR" = "blue" ]; then
  INACTIVE_COLOR="green"
else
  INACTIVE_COLOR="blue"
fi

log "Active color:   $ACTIVE_COLOR (currently serving traffic)"
log "Inactive color: $INACTIVE_COLOR (will receive new version)"
log "New version:    $NEW_VERSION"
log "New image:      $NEW_IMAGE"

# ── Step 2: Deploy to Inactive Color ─────────────────────────
heading "Step 2: Deploying to $INACTIVE_COLOR"

# Patch the inactive deployment with the new image and version
kubectl set image \
  deployment/url-shortener-$INACTIVE_COLOR \
  app=$NEW_IMAGE \
  -n "$NAMESPACE"

kubectl patch deployment url-shortener-$INACTIVE_COLOR \
  -n "$NAMESPACE" \
  -p "{
    \"spec\": {
      \"template\": {
        \"metadata\": {
          \"labels\": {
            \"version\": \"$NEW_VERSION\"
          }
        },
        \"spec\": {
          \"containers\": [{
            \"name\": \"app\",
            \"env\": [
              {\"name\": \"APP_VERSION\", \"value\": \"$NEW_VERSION\"},
              {\"name\": \"DEPLOYMENT_COLOR\", \"value\": \"$INACTIVE_COLOR\"}
            ]
          }]
        }
      }
    }
  }"

log "Deployment updated. Waiting for rollout..."

# Wait for inactive deployment to be fully ready
kubectl rollout status \
  deployment/url-shortener-$INACTIVE_COLOR \
  -n "$NAMESPACE" \
  --timeout=300s

log "✅ $INACTIVE_COLOR deployment is ready"

# ── Step 3: Point Test Service at Inactive ────────────────────
heading "Step 3: Configuring Test Service → $INACTIVE_COLOR"

kubectl patch service url-shortener-test \
  -n "$NAMESPACE" \
  -p "{\"spec\": {\"selector\": {\"color\": \"$INACTIVE_COLOR\"}}}"

log "Test service now routes to $INACTIVE_COLOR"

# Give pods a moment to register with the service
sleep 5

# ── Step 4: Smoke Test the Inactive Deployment ────────────────
heading "Step 4: Running Smoke Tests on $INACTIVE_COLOR"

# Port-forward the test service so we can reach it
kubectl port-forward \
  service/url-shortener-test \
  9999:80 \
  -n "$NAMESPACE" &
PF_PID=$!
sleep 3

log "Testing $INACTIVE_COLOR via port-forward..."

if bash "$(dirname $0)/../tests/smoke-test.sh" \
    "http://localhost:9999" \
    "$NEW_VERSION" \
    "$INACTIVE_COLOR"; then
  log "✅ All smoke tests passed!"
  kill $PF_PID 2>/dev/null
else
  error "Smoke tests FAILED on $INACTIVE_COLOR"
  kill $PF_PID 2>/dev/null

  warn "Rolling back $INACTIVE_COLOR to previous image..."
  kubectl rollout undo \
    deployment/url-shortener-$INACTIVE_COLOR \
    -n "$NAMESPACE"

  error "Deployment ABORTED. $ACTIVE_COLOR is still serving traffic."
  exit 1
fi

# ── Step 5: Switch Production Traffic ────────────────────────
heading "Step 5: Switching Production Traffic → $INACTIVE_COLOR"

warn "This is the actual switch. Production traffic will move to $INACTIVE_COLOR."
echo "Switching in 3 seconds... (Ctrl+C to abort)"
sleep 3

# Patch BOTH services:
# 1. Production service → points to new (inactive becomes active)
# 2. Test service → points to old (old active becomes test target)
# 3. External service → follows production

kubectl patch service url-shortener \
  -n "$NAMESPACE" \
  -p "{
    \"spec\": {\"selector\": {\"color\": \"$INACTIVE_COLOR\"}},
    \"metadata\": {
      \"annotations\": {
        \"service.kubernetes.io/active-color\": \"$INACTIVE_COLOR\"
      }
    }
  }"

kubectl patch service url-shortener-external \
  -n "$NAMESPACE" \
  -p "{\"spec\": {\"selector\": {\"color\": \"$INACTIVE_COLOR\"}}}"

kubectl patch service url-shortener-test \
  -n "$NAMESPACE" \
  -p "{\"spec\": {\"selector\": {\"color\": \"$ACTIVE_COLOR\"}}}"

log "✅ Switch complete!"
log "   Production: → $INACTIVE_COLOR ($NEW_VERSION)"
log "   Test service: → $ACTIVE_COLOR (old version)"

# ── Step 6: Verify Switch ─────────────────────────────────────
heading "Step 6: Verifying Production Switch"

sleep 5

MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "localhost")
PROD_COLOR=$(curl -s --max-time 10 \
  "http://$MINIKUBE_IP:30080/version" 2>/dev/null | \
  python3 -c \
  "import sys,json
try:
    print(json.load(sys.stdin).get('color','unknown'))
except:
    print('error')" 2>/dev/null)

if [ "$PROD_COLOR" = "$INACTIVE_COLOR" ]; then
  log "✅ Verified: Production is now serving $INACTIVE_COLOR ($NEW_VERSION)"
else
  error "Verification failed! Expected $INACTIVE_COLOR but got $PROD_COLOR"
  warn "Manual investigation required."
  exit 1
fi

# ── Step 7: Summary ───────────────────────────────────────────
heading "Deployment Complete"

echo ""
echo "  Previous (standby): $ACTIVE_COLOR"
echo "  Current  (active):  $INACTIVE_COLOR ($NEW_VERSION)"
echo ""
echo "  Rollback command:"
echo "  kubectl patch service url-shortener -n $NAMESPACE \\"
echo "    -p '{\"spec\": {\"selector\": {\"color\": \"$ACTIVE_COLOR\"}}}'"
echo ""
echo "  Scale down old version (after confidence):"
echo "  kubectl scale deployment url-shortener-$ACTIVE_COLOR \\"
echo "    --replicas=0 -n $NAMESPACE"
echo ""
log "Blue-green deployment successful! 🚀"
