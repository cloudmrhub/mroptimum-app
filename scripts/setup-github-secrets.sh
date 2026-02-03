#!/bin/bash
#
# Setup GitHub Secrets for MR Optimum CI/CD Pipeline
#
# Run this script to configure the required secrets in your GitHub repository.
# Requires GitHub CLI (gh) to be installed and authenticated.
#
# Usage:
#   ./setup-github-secrets.sh <owner/repo>
#
# Example:
#   ./setup-github-secrets.sh cloudmrhub/mroptimum-app
#

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <owner/repo>"
    echo "Example: $0 cloudmrhub/mroptimum-app"
    exit 1
fi

REPO="$1"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   MR Optimum CI/CD Secrets Setup                              ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Repository: $REPO"
echo ""

# Check for gh CLI
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Install it from: https://cli.github.com/"
    exit 1
fi

# Check authentication
if ! gh auth status &> /dev/null; then
    echo "Error: GitHub CLI is not authenticated."
    echo "Run: gh auth login"
    exit 1
fi

echo "This script will set the following secrets:"
echo "  - AWS_DEPLOY_ROLE_ARN"
echo "  - CLOUDMR_API_HOST"
echo "  - CLOUDMR_API_URL"
echo "  - CLOUDMR_ADMIN_TOKEN"
echo "  - ECS_CLUSTER_NAME"
echo "  - SUBNET_ID_1"
echo "  - SUBNET_ID_2"
echo "  - SECURITY_GROUP_ID"
echo "  - RESULTS_BUCKET"
echo "  - FAILED_BUCKET"
echo "  - DATA_BUCKET"
echo ""

# Get values
read -p "AWS IAM Role ARN for deployment (OIDC): " AWS_DEPLOY_ROLE_ARN
read -p "CloudMR Brain API Host (e.g., api.cloudmrhub.com): " CLOUDMR_API_HOST
CLOUDMR_API_URL="https://${CLOUDMR_API_HOST}"
read -sp "CloudMR Admin Token: " CLOUDMR_ADMIN_TOKEN
echo ""
read -p "ECS Cluster Name [mroptimum-cluster]: " ECS_CLUSTER_NAME
ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME:-mroptimum-cluster}"
read -p "Subnet ID 1: " SUBNET_ID_1
read -p "Subnet ID 2: " SUBNET_ID_2
read -p "Security Group ID: " SECURITY_GROUP_ID
read -p "Results Bucket Name: " RESULTS_BUCKET
read -p "Failed Bucket Name: " FAILED_BUCKET
read -p "Data Bucket Name: " DATA_BUCKET

echo ""
echo "Setting secrets..."

gh secret set AWS_DEPLOY_ROLE_ARN --repo "$REPO" --body "$AWS_DEPLOY_ROLE_ARN"
gh secret set CLOUDMR_API_HOST --repo "$REPO" --body "$CLOUDMR_API_HOST"
gh secret set CLOUDMR_API_URL --repo "$REPO" --body "$CLOUDMR_API_URL"
gh secret set CLOUDMR_ADMIN_TOKEN --repo "$REPO" --body "$CLOUDMR_ADMIN_TOKEN"
gh secret set ECS_CLUSTER_NAME --repo "$REPO" --body "$ECS_CLUSTER_NAME"
gh secret set SUBNET_ID_1 --repo "$REPO" --body "$SUBNET_ID_1"
gh secret set SUBNET_ID_2 --repo "$REPO" --body "$SUBNET_ID_2"
gh secret set SECURITY_GROUP_ID --repo "$REPO" --body "$SECURITY_GROUP_ID"
gh secret set RESULTS_BUCKET --repo "$REPO" --body "$RESULTS_BUCKET"
gh secret set FAILED_BUCKET --repo "$REPO" --body "$FAILED_BUCKET"
gh secret set DATA_BUCKET --repo "$REPO" --body "$DATA_BUCKET"

echo ""
echo "✅ All secrets have been set successfully!"
echo ""
echo "To verify, run:"
echo "  gh secret list --repo $REPO"
