#!/usr/bin/env bash
# Set all GitHub Actions secrets used by the Mode1 workflow.
# Usage:
#   ./set-all-secrets.sh <owner/repo>./scripts/set-all-secrets.sh cloudmrhub/mroptimum-app
# The script reads values from environment variables if present, otherwise prompts.

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <owner/repo>"
  echo "Example: $0 cloudmrhub/mroptimum-app"
  exit 1
fi
REPO="$1"

# Helper to read secret from env or prompt
read_secret() {
  local name="$1"
  local prompt="$2"
  local envvar_val=${!name:-}
  if [ -n "$envvar_val" ]; then
    echo "$envvar_val"
    return 0
  fi
  # If not set, prompt (hidden input for passwords/tokens)
  if [[ "$name" =~ PASSWORD|TOKEN ]]; then
    read -rsp "$prompt: " val
    echo
  else
    read -rp "$prompt: " val
  fi
  echo "$val"
}

# Require gh
if ! command -v gh &> /dev/null; then
  echo "Error: GitHub CLI (gh) is not installed."
  exit 1
fi
if ! gh auth status &> /dev/null; then
  echo "Error: GitHub CLI not authenticated. Run: gh auth login"
  exit 1
fi

echo "Repository: $REPO"

# Collect values (use environment variables if present)
AWS_DEPLOY_ROLE_ARN=$(read_secret AWS_DEPLOY_ROLE_ARN "AWS IAM Role ARN for OIDC (AWS_DEPLOY_ROLE_ARN)")
CLOUDMR_API_HOST=$(read_secret CLOUDMR_API_HOST "CloudMR API host (e.g. api.cloudmrhub.com) (CLOUDMR_API_HOST)")
CLOUDMR_API_URL=${CLOUDMR_API_URL:-}
if [ -z "$CLOUDMR_API_URL" ]; then
  CLOUDMR_API_URL="https://${CLOUDMR_API_HOST}"
fi

# Auth: either token or email+password
CLOUDMR_ADMIN_TOKEN=$(read_secret CLOUDMR_ADMIN_TOKEN "CloudMR admin token (CLOUDMR_ADMIN_TOKEN) - leave empty to use email+password")
CLOUDMR_ADMIN_EMAIL=$(read_secret CLOUDMR_ADMIN_EMAIL "CloudMR admin email (CLOUDMR_ADMIN_EMAIL) - used with password to auto-login")
CLOUDMR_ADMIN_PASSWORD=$(read_secret CLOUDMR_ADMIN_PASSWORD "CloudMR admin password (CLOUDMR_ADMIN_PASSWORD)")

ECS_CLUSTER_NAME=$(read_secret ECS_CLUSTER_NAME "ECS cluster name (ECS_CLUSTER_NAME) [mroptimum-cluster]")
ECS_CLUSTER_NAME=${ECS_CLUSTER_NAME:-mroptimum-cluster}
SUBNET_ID_1=$(read_secret SUBNET_ID_1 "Subnet ID 1 (SUBNET_ID_1)")
SUBNET_ID_2=$(read_secret SUBNET_ID_2 "Subnet ID 2 (SUBNET_ID_2)")
SECURITY_GROUP_ID=$(read_secret SECURITY_GROUP_ID "Security Group ID (SECURITY_GROUP_ID)")
RESULTS_BUCKET=$(read_secret RESULTS_BUCKET "Results bucket name (RESULTS_BUCKET)")
FAILED_BUCKET=$(read_secret FAILED_BUCKET "Failed bucket name (FAILED_BUCKET)")
DATA_BUCKET=$(read_secret DATA_BUCKET "Data bucket name (DATA_BUCKET)")

echo
echo "Setting secrets in GitHub repository: $REPO"

gh secret set AWS_DEPLOY_ROLE_ARN --repo "$REPO" --body "$AWS_DEPLOY_ROLE_ARN"
gh secret set CLOUDMR_API_HOST --repo "$REPO" --body "$CLOUDMR_API_HOST"
gh secret set CLOUDMR_API_URL --repo "$REPO" --body "$CLOUDMR_API_URL"

# For admin auth, set either token or email+password
if [ -n "$CLOUDMR_ADMIN_TOKEN" ]; then
  gh secret set CLOUDMR_ADMIN_TOKEN --repo "$REPO" --body "$CLOUDMR_ADMIN_TOKEN"
fi
if [ -n "$CLOUDMR_ADMIN_EMAIL" ]; then
  gh secret set CLOUDMR_ADMIN_EMAIL --repo "$REPO" --body "$CLOUDMR_ADMIN_EMAIL"
fi
if [ -n "$CLOUDMR_ADMIN_PASSWORD" ]; then
  gh secret set CLOUDMR_ADMIN_PASSWORD --repo "$REPO" --body "$CLOUDMR_ADMIN_PASSWORD"
fi

gh secret set ECS_CLUSTER_NAME --repo "$REPO" --body "$ECS_CLUSTER_NAME"
gh secret set SUBNET_ID_1 --repo "$REPO" --body "$SUBNET_ID_1"
gh secret set SUBNET_ID_2 --repo "$REPO" --body "$SUBNET_ID_2"
gh secret set SECURITY_GROUP_ID --repo "$REPO" --body "$SECURITY_GROUP_ID"
gh secret set RESULTS_BUCKET --repo "$REPO" --body "$RESULTS_BUCKET"
gh secret set FAILED_BUCKET --repo "$REPO" --body "$FAILED_BUCKET"
gh secret set DATA_BUCKET --repo "$REPO" --body "$DATA_BUCKET"

echo
echo "✅ Secrets set. To verify run: gh secret list --repo $REPO"
