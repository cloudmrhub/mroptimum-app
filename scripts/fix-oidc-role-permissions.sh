#!/usr/bin/env bash
# Fix OIDC role permissions for GitHub Actions
# Adds EC2 describe permissions required by SAM deploy

set -euo pipefail

ROLE_NAME="GitHubActionsRole-mroptimum-app"
AWS_PROFILE="${AWS_PROFILE:-nyu}"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Fixing OIDC Role Permissions                                ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Role Name: ${ROLE_NAME}"
echo "AWS Profile: ${AWS_PROFILE}"
echo ""

# Check if role exists
if ! aws iam get-role --role-name "$ROLE_NAME" --profile "$AWS_PROFILE" &>/dev/null; then
  echo "❌ Role ${ROLE_NAME} not found"
  echo "Run ./scripts/create-github-oidc-role.sh first"
  exit 1
fi

echo "✓ Role exists"
echo ""

# Create policy document with EC2 describe permissions
POLICY_DOC=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2NetworkDescribe",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeAvailabilityZones"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

POLICY_NAME="GitHubActions-EC2Describe"

echo "Creating/updating inline policy: ${POLICY_NAME}"

# Put inline policy on the role
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --policy-document "$POLICY_DOC" \
  --profile "$AWS_PROFILE"

echo "✓ Inline policy added to role"
echo ""

# Verify the policy was added
echo "Verifying policy..."
aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "$POLICY_NAME" \
  --profile "$AWS_PROFILE" \
  --query 'PolicyDocument' \
  --output json | jq .

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   ✓ Permissions Updated                                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "The GitHub Actions OIDC role now has EC2 describe permissions."
echo "Re-run the failed workflow to deploy the stack."
