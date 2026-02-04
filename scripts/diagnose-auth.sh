#!/usr/bin/env bash
set -euo pipefail

# Diagnostic script to test computing-unit/register endpoint and identify authorization issues

echo "CloudMR Brain API Authorization Diagnostic"
echo "==========================================="
echo ""

# Load environment
if [ -f "exports.sh" ]; then
  source exports.sh
fi

ENDPOINT="${CLOUDM_MR_BRAIN:-}"
TOKEN="${ADMIN_ID_TOKEN:-${ID_TOKEN:-}}"

if [ -z "$ENDPOINT" ]; then
  echo "ERROR: CLOUDM_MR_BRAIN not set. Export it or source exports.sh" >&2
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "ERROR: No ID_TOKEN or ADMIN_ID_TOKEN found. Export one before running." >&2
  exit 1
fi

# Sanitize token
TOKEN_CLEAN=$(printf '%s' "$TOKEN" | tr -d '\r\n' | sed 's/^"//; s/"$//')

echo "Endpoint: $ENDPOINT"
echo "Token (first 20 chars): ${TOKEN_CLEAN:0:20}..."
echo "Token length: $(echo -n "$TOKEN_CLEAN" | wc -c)"
echo ""

# Decode JWT payload
echo "JWT Claims:"
echo "$TOKEN_CLEAN" | cut -d. -f2 | base64 --decode 2>/dev/null | jq . || echo "(failed to decode)"
echo ""

# Test 1: List computing units (GET - should work with same auth)
echo "Test 1: GET /api/computing-unit/list"
RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" -G \
  -H "Authorization: Bearer $TOKEN_CLEAN" \
  "$ENDPOINT/api/computing-unit/list" \
  --data-urlencode "appName=MR Optimum")

HTTP_CODE=$(echo "$RESP" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESP" | sed '/HTTP_CODE:/d')

echo "Status: $HTTP_CODE"
echo "Response:"
echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
echo ""

if [ "$HTTP_CODE" != "200" ]; then
  echo "❌ List endpoint failed with $HTTP_CODE"
  echo "This suggests the token or endpoint configuration has an issue."
  exit 1
fi

echo "✓ List endpoint succeeded"
echo ""

# Test 2: Register computing unit (POST)
echo "Test 2: POST /api/computing-unit/register"
PAYLOAD='{
  "appName": "MR Optimum",
  "mode": "mode1",
  "provider": "cloudmrhub",
  "awsAccountId": "469266894233",
  "region": "us-east-1",
  "stateMachineArn": "arn:aws:states:us-east-1:469266894233:stateMachine:test",
  "resultsBucket": "test-results",
  "failedBucket": "test-failed",
  "dataBucket": "test-data",
  "isDefault": true
}'

RESP=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
  -H "Authorization: Bearer $TOKEN_CLEAN" \
  -H "Content-Type: application/json" \
  "$ENDPOINT/api/computing-unit/register" \
  -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESP" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESP" | sed '/HTTP_CODE:/d')

echo "Status: $HTTP_CODE"
echo "Response:"
echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
echo ""

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "✓ Register endpoint succeeded"
elif [ "$HTTP_CODE" = "403" ]; then
  echo "❌ Register endpoint returned 403"
  echo "Common causes:"
  echo "  - Token not in Admins group (check JWT claims above)"
  echo "  - API Gateway authorizer misconfigured"
  echo "  - CORS preflight issue"
else
  echo "❌ Register endpoint failed with unexpected code $HTTP_CODE"
fi

echo ""
echo "Done."
