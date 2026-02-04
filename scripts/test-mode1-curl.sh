#!/bin/bash
#
# Quick Test - Submit a calculation via CloudMR Brain API
#
# This tests the full end-to-end flow:
# 1. CloudMR Brain receives request
# 2. Routes to Mode 1 computing unit
# 3. Executes on deployed infrastructure
#

set -e

CLOUDMR_API_URL="${CLOUDMR_API_URL:-}"
CLOUDMR_TOKEN="${CLOUDMR_TOKEN:-}"
APP_ID="mroptimum"

if [ -z "$CLOUDMR_API_URL" ]; then
    echo "❌ CLOUDMR_API_URL not set"
    echo ""
    echo "Usage:"
    echo "  export CLOUDMR_API_URL=https://your-api.com"
    echo "  export CLOUDMR_TOKEN=your_jwt_token"
    echo "  ./scripts/test-mode1-curl.sh"
    exit 1
fi

if [ -z "$CLOUDMR_TOKEN" ]; then
    echo "⚠ CLOUDMR_TOKEN not set"
    echo ""
    read -p "Username: " USERNAME
    read -sp "Password: " PASSWORD
    echo ""
    
    # Login
    echo "Logging in..."
    LOGIN_RESPONSE=$(curl -s -X POST "${CLOUDMR_API_URL}/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"${USERNAME}\", \"password\": \"${PASSWORD}\"}")
    
    CLOUDMR_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token // empty')
    
    if [ -z "$CLOUDMR_TOKEN" ]; then
        echo "❌ Login failed"
        echo "$LOGIN_RESPONSE" | jq .
        exit 1
    fi
    
    echo "✅ Logged in"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Test Mode 1 via CloudMR Brain API                           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "API URL: $CLOUDMR_API_URL"
echo "App ID:  $APP_ID"
echo ""

# List computing units
echo "Checking available computing units..."
UNITS=$(curl -s -X GET "${CLOUDMR_API_URL}/api/computing-unit/list?appId=${APP_ID}" \
    -H "Authorization: Bearer ${CLOUDMR_TOKEN}")

echo "$UNITS" | jq -r '.[] | "  - \(.mode) (\(.provider)) \(if .isDefault then "[DEFAULT]" else "" end)"'
echo ""

# Create test payload
PAYLOAD=$(cat <<EOF
{
  "appId": "${APP_ID}",
  "task": {
    "name": "test_brain_calculation",
    "type": "brain",
    "options": {
      "test": true,
      "slices": 3
    }
  },
  "inputs": {
    "data": "s3://test-bucket/sample-brain.dat"
  },
  "output": {
    "format": "json"
  }
}
EOF
)

echo "Submitting test calculation..."
echo "$PAYLOAD" | jq .
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${CLOUDMR_API_URL}/api/pipeline/request" \
    -H "Authorization: Bearer ${CLOUDMR_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    echo "❌ Request failed (HTTP $HTTP_CODE)"
    echo "$BODY" | jq .
    exit 1
fi

PIPELINE_ID=$(echo "$BODY" | jq -r '.pipelineId // .id // empty')

if [ -z "$PIPELINE_ID" ]; then
    echo "❌ No pipeline ID returned"
    echo "$BODY" | jq .
    exit 1
fi

echo "✅ Request submitted!"
echo "   Pipeline ID: $PIPELINE_ID"
echo ""

# Monitor status
echo "Monitoring status (Ctrl+C to stop)..."
echo ""

LAST_STATUS=""
START_TIME=$(date +%s)
MAX_WAIT=600  # 10 minutes

while true; do
    ELAPSED=$(($(date +%s) - START_TIME))
    
    if [ $ELAPSED -gt $MAX_WAIT ]; then
        echo "⚠ Timeout after ${MAX_WAIT}s"
        break
    fi
    
    STATUS_RESPONSE=$(curl -s -X GET "${CLOUDMR_API_URL}/api/pipeline/status/${PIPELINE_ID}" \
        -H "Authorization: Bearer ${CLOUDMR_TOKEN}")
    
    CURRENT_STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status // "UNKNOWN"')
    
    if [ "$CURRENT_STATUS" != "$LAST_STATUS" ]; then
        TIMESTAMP=$(date +%H:%M:%S)
        echo "[$TIMESTAMP] Status: $CURRENT_STATUS"
        LAST_STATUS="$CURRENT_STATUS"
    fi
    
    # Check terminal states
    case "$CURRENT_STATUS" in
        SUCCEEDED|COMPLETED|DONE)
            echo ""
            echo "✅ Pipeline SUCCEEDED in ${ELAPSED}s"
            echo ""
            echo "Final status:"
            echo "$STATUS_RESPONSE" | jq .
            exit 0
            ;;
        FAILED|ERROR)
            echo ""
            echo "❌ Pipeline FAILED"
            echo ""
            echo "Error details:"
            echo "$STATUS_RESPONSE" | jq .
            exit 1
            ;;
        UNKNOWN)
            echo ""
            echo "⚠ Unknown status"
            echo "$STATUS_RESPONSE" | jq .
            break
            ;;
    esac
    
    sleep 5
done

echo ""
echo "Check status manually:"
echo "  curl -H 'Authorization: Bearer \$CLOUDMR_TOKEN' ${CLOUDMR_API_URL}/api/pipeline/status/${PIPELINE_ID}"
