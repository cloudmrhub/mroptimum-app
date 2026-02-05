#!/bin/bash
# filepath: /data/PROJECTS/mroptimum-app/scripts/quick-queue-test.sh

# =============================================================================
# Quick Queue Test - One-shot job submission
# =============================================================================
# Usage: 
#   export CLOUDMR_EMAIL="your@email.com"
#   export CLOUDMR_PASSWORD="yourpassword"
#   ./scripts/quick-queue-test.sh
# =============================================================================

set -e

CLOUDMR_API_URL="${CLOUDMR_API_URL:-https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod}"

echo "=== CloudMR Brain Quick Queue Test ==="
echo "API: $CLOUDMR_API_URL"
echo ""

# Check credentials
if [[ -z "$CLOUDMR_EMAIL" || -z "$CLOUDMR_PASSWORD" ]]; then
    echo "Please set CLOUDMR_EMAIL and CLOUDMR_PASSWORD environment variables"
    echo ""
    echo "Example:"
    echo "  export CLOUDMR_EMAIL='your@email.com'"
    echo "  export CLOUDMR_PASSWORD='yourpassword'"
    exit 1
fi

# Step 1: Login
echo "[1/4] Logging in..."

# Use jq to properly escape special characters in JSON
LOGIN_PAYLOAD=$(jq -n --arg email "$CLOUDMR_EMAIL" --arg password "$CLOUDMR_PASSWORD" \
    '{email: $email, password: $password}')

LOGIN_RESPONSE=$(curl -s -X POST "${CLOUDMR_API_URL}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "$LOGIN_PAYLOAD")

# API returns snake_case: id_token, access_token, etc.
ID_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.id_token // .idToken // empty')

if [[ -z "$ID_TOKEN" ]]; then
    echo "Login failed!"
    echo "$LOGIN_RESPONSE" | jq '.'
    exit 1
fi
echo "  ✓ Login successful"

# Step 2: Find MR Optimum CloudApp
echo "[2/4] Finding MR Optimum CloudApp..."
APPS_RESPONSE=$(curl -s -X GET "${CLOUDMR_API_URL}/api/cloudapp/list" \
    -H "Authorization: Bearer ${ID_TOKEN}")

CLOUDAPP_ID=$(echo "$APPS_RESPONSE" | jq -r '.[] | select(.name == "MR Optimum") | .appId // empty')

if [[ -z "$CLOUDAPP_ID" ]]; then
    echo "MR Optimum CloudApp not found!"
    echo "Available apps:"
    echo "$APPS_RESPONSE" | jq -r '.[].name'
    exit 1
fi
echo "  ✓ Found CloudApp ID: $CLOUDAPP_ID"

# Step 3: Create Pipeline
echo "[3/4] Creating pipeline..."
PIPELINE_NAME="Test-$(date +%Y%m%d-%H%M%S)"

PIPELINE_RESPONSE=$(curl -s -X POST "${CLOUDMR_API_URL}/api/pipeline/request" \
    -H "Authorization: Bearer ${ID_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
        \"cloudapp_id\": \"${CLOUDAPP_ID}\",
        \"name\": \"${PIPELINE_NAME}\"
    }")

PIPELINE_ID=$(echo "$PIPELINE_RESPONSE" | jq -r '.pipeline // .pipelineId // empty')

if [[ -z "$PIPELINE_ID" ]]; then
    echo "Failed to create pipeline!"
    echo "$PIPELINE_RESPONSE" | jq '.'
    exit 1
fi
echo "  ✓ Created Pipeline ID: $PIPELINE_ID"

# Step 4: Queue Job
echo "[4/4] Queueing job..."

QUEUE_RESPONSE=$(curl -s -X POST "${CLOUDMR_API_URL}/api/pipeline/queue_job" \
    -H "Authorization: Bearer ${ID_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{
        \"pipeline\": \"${PIPELINE_ID}\",
        \"cloudapp_id\": \"${CLOUDAPP_ID}\",
        \"task\": {
            \"type\": \"test\",
            \"parameters\": {
                \"test_mode\": true,
                \"timestamp\": \"$(date -Iseconds)\"
            }
        }
    }")

echo ""
echo "=== Queue Response ==="
echo "$QUEUE_RESPONSE" | jq '.'

EXECUTION_ARN=$(echo "$QUEUE_RESPONSE" | jq -r '.executionArn // empty')
if [[ -n "$EXECUTION_ARN" ]]; then
    echo ""
    echo "=== SUCCESS ==="
    echo "Execution ARN: $EXECUTION_ARN"
    echo ""
    echo "Monitor execution at:"
    echo "https://us-east-1.console.aws.amazon.com/states/home?region=us-east-1#/executions/details/${EXECUTION_ARN}"
fi