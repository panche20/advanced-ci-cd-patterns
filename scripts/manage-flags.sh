#!/bin/bash
# ── Feature Flag Management ───────────────────────────────────
# Control feature releases without code deployments.
# All flag changes take effect immediately — no restart needed.
#
# Usage:
#   ./manage-flags.sh list
#   ./manage-flags.sh enable analytics_enabled
#   ./manage-flags.sh disable new_ui_enabled
#   ./manage-flags.sh rollout custom_slugs_enabled 25
#   ./manage-flags.sh users bulk_shorten_enabled user1,user2

BASE_URL="${FEATURE_FLAG_URL:-http://$(minikube ip 2>/dev/null):30080}"
COMMAND="$1"
FLAG_NAME="$2"
VALUE="$3"

case "$COMMAND" in
  list)
    echo "=== Current Feature Flags ==="
    curl -s "$BASE_URL/flags" | python3 -m json.tool
    ;;

  enable)
    echo "Enabling flag: $FLAG_NAME"
    curl -s -X POST "$BASE_URL/flags/$FLAG_NAME" \
      -H "Content-Type: application/json" \
      -d '{"value": true}' | python3 -m json.tool
    ;;

  disable)
    echo "Disabling flag: $FLAG_NAME"
    curl -s -X POST "$BASE_URL/flags/$FLAG_NAME" \
      -H "Content-Type: application/json" \
      -d '{"value": false}' | python3 -m json.tool
    ;;

  rollout)
    # Gradual percentage rollout
    PERCENTAGE="${VALUE:-10}"
    echo "Rolling out $FLAG_NAME to ${PERCENTAGE}% of users"
    curl -s -X POST "$BASE_URL/flags/$FLAG_NAME" \
      -H "Content-Type: application/json" \
      -d "{\"value\": {\"percentage\": $PERCENTAGE}}" | python3 -m json.tool
    ;;

  users)
    # Enable for specific users
    IFS=',' read -ra USER_ARRAY <<< "$VALUE"
    USERS_JSON=$(printf '"%s",' "${USER_ARRAY[@]}" | sed 's/,$//')
    echo "Enabling $FLAG_NAME for users: $VALUE"
    curl -s -X POST "$BASE_URL/flags/$FLAG_NAME" \
      -H "Content-Type: application/json" \
      -d "{\"value\": {\"users\": [$USERS_JSON]}}" | python3 -m json.tool
    ;;

  *)
    echo "Usage: $0 <command> [flag_name] [value]"
    echo ""
    echo "Commands:"
    echo "  list                         List all flags"
    echo "  enable <flag>                Enable for all users"
    echo "  disable <flag>               Disable for all users"
    echo "  rollout <flag> <percentage>  Enable for X% of users"
    echo "  users <flag> <user1,user2>   Enable for specific users"
    echo ""
    echo "Available flags:"
    echo "  analytics_enabled"
    echo "  custom_slugs_enabled"
    echo "  rate_limiting_enabled"
    echo "  new_ui_enabled"
    echo "  bulk_shorten_enabled"
    ;;
esac
