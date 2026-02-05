#!/usr/bin/env bash
set -euo pipefail

# Register Mode1 computing unit if missing; checks CloudApp first.
# Usage: Set environment variables `CLOUDM_MR_BRAIN`, `ADMIN_ID_TOKEN`,
# `AWS_ACCOUNT_ID`, `STATE_MACHINE_ARN`, `RESULTS_BUCKET`, `FAILED_BUCKET`, `DATA_BUCKET`.

APP_NAME=${APP_NAME:-"MR Optimum"}
COMPUTING_UNIT_MODE=${COMPUTING_UNIT_MODE:-"mode_1a"}
CLOUDM_MR_BRAIN=${CLOUDM_MR_BRAIN:-}
ADMIN_ID_TOKEN=${ADMIN_ID_TOKEN:-}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-}
REGION=${REGION:-"us-east-1"}
STATE_MACHINE_ARN=${STATE_MACHINE_ARN:-}
RESULTS_BUCKET=${RESULTS_BUCKET:-}
FAILED_BUCKET=${FAILED_BUCKET:-}
DATA_BUCKET=${DATA_BUCKET:-}

print_usage() {
  cat <<EOF
Usage: CLOUDM_MR_BRAIN=https://... ADMIN_ID_TOKEN=xxx \
  AWS_ACCOUNT_ID=123456789012 STATE_MACHINE_ARN=arn:aws:states:... \
  RESULTS_BUCKET=my-results FAILED_BUCKET=my-failed DATA_BUCKET=my-data \
  ./scripts/register-mode1.sh

Optional envs: APP_NAME (default: "MR Optimum"), REGION (default: us-east-1),
  COMPUTING_UNIT_MODE (default: "mode_1a")
EOF
}

if [[ -z "$CLOUDM_MR_BRAIN" || -z "$ADMIN_ID_TOKEN" || -z "$AWS_ACCOUNT_ID" || -z "$STATE_MACHINE_ARN" || -z "$RESULTS_BUCKET" || -z "$FAILED_BUCKET" || -z "$DATA_BUCKET" ]]; then
  echo "Missing required environment variables."
  print_usage
  exit 2
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required. Install it and retry."; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "curl is required. Install it and retry."; exit 2; }

echo "Using CloudMR Brain endpoint: $CLOUDM_MR_BRAIN"
echo "Checking for CloudApp named: '$APP_NAME'"

# Sanitize token once for all curl calls (remove newlines and surrounding quotes)
ADMIN_ID_TOKEN_CLEAN=$(printf '%s' "$ADMIN_ID_TOKEN" | tr -d '\r\n' | sed 's/^"//; s/"$//')

# Helper: naive URL-encode for spaces only (good enough for app names with spaces)
app_encoded=${APP_NAME// /%20}

get_cloudapp() {
  curl -s -H "Authorization: Bearer $ADMIN_ID_TOKEN_CLEAN" "$CLOUDM_MR_BRAIN/api/cloudapp/list" \
    | jq -r --arg name "$APP_NAME" '.apps[]? | select(.name==$name) | .appId' || true
}

APP_ID=$(get_cloudapp)

if [[ -n "$APP_ID" && "$APP_ID" != "null" ]]; then
  echo "CloudApp exists with appId: $APP_ID"
else
  echo "CloudApp not found; creating CloudApp named '$APP_NAME'..."
  resp=$(curl -s -X POST "$CLOUDM_MR_BRAIN/api/cloudapp/create" \
    -H "Authorization: Bearer $ADMIN_ID_TOKEN_CLEAN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$APP_NAME\", \"description\": \"MRI optimization and analysis application\", \"launchUrl\": \"https://mr-optimum.example.com\"}")
  APP_ID=$(echo "$resp" | jq -r '.data.app.appId // .appId // empty') || true
  if [[ -z "$APP_ID" ]]; then
    echo "Failed to create CloudApp. Response:" >&2
    echo "$resp" | jq . >&2 || true
    exit 3
  fi
  echo "Created CloudApp with appId: $APP_ID"
fi

echo "Checking for existing computing unit for app '$APP_NAME' with mode '$COMPUTING_UNIT_MODE'"
# NOTE: These endpoints use /api/ prefix (fixed in cloudmr-brain template)
cu_list=$(curl -s -G -H "Authorization: Bearer $ADMIN_ID_TOKEN_CLEAN" "$CLOUDM_MR_BRAIN/api/computing-unit/list" --data-urlencode "appName=$APP_NAME")
existing_cu=$(echo "$cu_list" | jq -r --arg mode "$COMPUTING_UNIT_MODE" --arg app "$APP_NAME" '.computingUnits[]? | select(.mode==$mode) | .computingUnitId' || true)

if [[ -n "$existing_cu" && "$existing_cu" != "null" ]]; then
  echo "Found existing computing unit(s) with mode=$COMPUTING_UNIT_MODE:"
  echo "$cu_list" | jq -r --arg mode "$COMPUTING_UNIT_MODE" '.computingUnits[]? | select(.mode==$mode)'
  echo "No further action required."
  exit 0
fi

echo "No computing unit found for mode '$COMPUTING_UNIT_MODE'. Registering a new one..."

register_payload=$(cat <<JSON
{
  "appName": "$APP_NAME",
  "mode": "$COMPUTING_UNIT_MODE",
  "provider": "aws",
  "awsAccountId": "$AWS_ACCOUNT_ID",
  "region": "$REGION",
  "stateMachineArn": "$STATE_MACHINE_ARN",
  "resultsBucket": "$RESULTS_BUCKET",
  "failedBucket": "$FAILED_BUCKET",
  "dataBucket": "$DATA_BUCKET",
  "isDefault": true
}
JSON
)

echo "Payload:"
echo "$register_payload" | jq .

# NOTE: These endpoints use /api/ prefix (fixed in cloudmr-brain template)
resp=$(curl -s -X POST "$CLOUDM_MR_BRAIN/api/computing-unit/register" \
  -H "Authorization: Bearer $ADMIN_ID_TOKEN_CLEAN" \
  -H "Content-Type: application/json" \
  -d "$register_payload")

echo "Register response:"
echo "$resp" | jq . || true

created_id=$(echo "$resp" | jq -r '.computingUnitId // .data.computingUnitId // empty') || true
if [[ -n "$created_id" ]]; then
  echo "Successfully registered computing unit: $created_id"
  echo "Verifying..."
  # NOTE: These endpoints use /api/ prefix (fixed in cloudmr-brain template)
  curl -s -G -H "Authorization: Bearer $ADMIN_ID_TOKEN_CLEAN" "$CLOUDM_MR_BRAIN/api/computing-unit/list" --data-urlencode "appName=$APP_NAME" | jq .
  exit 0
else
  echo "Registration may have failed. See response above." >&2
  exit 4
fi
