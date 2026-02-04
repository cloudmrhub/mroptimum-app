#!/usr/bin/env bash
set -euo pipefail

# Wrapper: deploy Mode1 stack, persist outputs, update exports.sh, and register computing unit
# Requires that you have valid AWS credentials and that `exports.sh` contains your login/admin token and
# `CLOUDM_MR_BRAIN` endpoint. The deploy script may prompt for network params unless you set them as env vars.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
cd "$ROOT_DIR"

echo "Starting Mode1 deploy+register wrapper"

if [ ! -f "exports.sh" ]; then
  echo "ERROR: exports.sh not found in repo root. Create it with your credentials and CLOUDM_MR_BRAIN." >&2
  exit 2
fi

echo "Sourcing existing exports.sh (this may perform login calls)"
# shellcheck disable=SC1091
source ./exports.sh

echo "Running deployment: ./scripts/deploy-mode1-local.sh"
# Ensure deploy script has an admin token available under the env var it expects
export ADMIN_ID_TOKEN=${ADMIN_ID_TOKEN:-$ID_TOKEN}
export CLOUDMR_ADMIN_TOKEN=${CLOUDMR_ADMIN_TOKEN:-$ADMIN_ID_TOKEN}
export CLOUDMR_API_URL=${CLOUDMR_API_URL:-$CLOUDM_MR_BRAIN}

./scripts/deploy-mode1-local.sh

EXPORTS_MODE1="exports.mode1.sh"
if [ ! -f "$EXPORTS_MODE1" ]; then
  echo "ERROR: Expected $EXPORTS_MODE1 to be produced by the deploy script but it was not found." >&2
  exit 3
fi

echo "Sourcing $EXPORTS_MODE1 to obtain Mode1 outputs"
# shellcheck disable=SC1091
source "$EXPORTS_MODE1"

echo "Updating ./exports.sh with Mode1 environment variables"
backup_ts=$(date --utc +%Y%m%dT%H%M%SZ)
cp exports.sh "exports.sh.bak.$backup_ts"

set_var() {
  local name="$1" val="$2"
  # Escape slashes for sed
  esc_val=$(printf '%s' "$val" | sed 's|\\|\\\\|g; s|/|\\/|g')
  if grep -qE "^export[[:space:]]+$name=" exports.sh; then
    sed -i "s/^export[[:space:]]\+$name=.*/export $name='$esc_val'/" exports.sh
  elif grep -qE "^export[[:space:]]*$name=" exports.sh; then
    sed -i "s/^export[[:space:]]*$name=.*/export $name='$esc_val'/" exports.sh
  else
    printf "\n# Mode1 auto-set (%s)\nexport %s='%s'\n" "$backup_ts" "$name" "$val" >> exports.sh
  fi
}

# Set the variables discovered by the deploy
set_var AWS_ACCOUNT_ID "$AWS_ACCOUNT_ID"
set_var STATE_MACHINE_ARN "$STATE_MACHINE_ARN"
set_var DATA_BUCKET "$DATA_BUCKET"
set_var FAILED_BUCKET "$FAILED_BUCKET"
set_var RESULTS_BUCKET "$RESULTS_BUCKET"

echo "Updated exports.sh (backup at exports.sh.bak.$backup_ts)"

echo "Registering computing unit via scripts/register-mode1.sh"
# Ensure required envs are exported for the register script
export CLOUDM_MR_BRAIN=${CLOUDM_MR_BRAIN:-}
export ADMIN_ID_TOKEN=${ADMIN_ID_TOKEN:-$ID_TOKEN}
export AWS_ACCOUNT_ID
export STATE_MACHINE_ARN
export RESULTS_BUCKET
export FAILED_BUCKET
export DATA_BUCKET

# Execute the registration script. If it's not executable, run it with bash.
if [ -x "./scripts/register-mode1.sh" ]; then
  ./scripts/register-mode1.sh
elif command -v bash >/dev/null 2>&1 && [ -r "./scripts/register-mode1.sh" ]; then
  echo "scripts/register-mode1.sh is not executable; running with bash..."
  bash ./scripts/register-mode1.sh
else
  echo "ERROR: Cannot run scripts/register-mode1.sh. Ensure the file exists and is executable or run 'chmod +x scripts/register-mode1.sh'" >&2
  exit 1
fi

echo "Verifying computing unit list from CloudMR Brain"
if [ -n "${CLOUDM_MR_BRAIN:-}" ] && [ -n "${ADMIN_ID_TOKEN:-}" ]; then
  curl -s -G -H "Authorization: Bearer $ADMIN_ID_TOKEN" "$CLOUDM_MR_BRAIN/api/computing-unit/list" --data-urlencode "appName=MR Optimum" | jq .
else
  echo "Skipping verification - CLOUDM_MR_BRAIN or ADMIN_ID_TOKEN missing in environment." >&2
fi

echo "Done. You can source ./exports.sh to load the new Mode1 variables."
