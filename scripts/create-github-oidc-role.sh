#!/bin/bash
#
# Create IAM Role for GitHub Actions OIDC
#
# This role allows GitHub Actions to assume permissions in your AWS account
# without storing long-lived credentials.
#

set -e

AWS_REGION="${AWS_REGION:-us-east-1}"
GITHUB_ORG="${1:-cloudmrhub}"
GITHUB_REPO="${2:-mroptimum-app}"
ROLE_NAME="GitHubActionsRole-${GITHUB_REPO}"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Create GitHub Actions OIDC Role                             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "GitHub Org:  $GITHUB_ORG"
echo "GitHub Repo: $GITHUB_REPO"
echo "Role Name:   $ROLE_NAME"
echo "Region:      $AWS_REGION"
echo ""

# Check if OIDC provider exists
OIDC_ARN=$(aws iam list-open-id-connect-providers \
    --query "OpenIDConnectProviderList[?ends_with(Arn, 'oidc-provider/token.actions.githubusercontent.com')].Arn" \
    --output text)

if [ -z "$OIDC_ARN" ]; then
    echo "Creating GitHub OIDC provider..."
    OIDC_ARN=$(aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
        --query "OpenIDConnectProviderArn" \
        --output text)
    echo "  ✓ Created OIDC provider: $OIDC_ARN"
else
    echo "  ✓ OIDC provider already exists: $OIDC_ARN"
fi

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create trust policy
TRUST_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                },
                "StringLike": {
                    "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
                }
            }
        }
    ]
}
EOF
)

# Create permissions policy
PERMISSIONS_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CloudFormation",
            "Effect": "Allow",
            "Action": [
                "cloudformation:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "S3",
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ECR",
            "Effect": "Allow",
            "Action": [
                "ecr:*",
                "ecr-public:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "IAM",
            "Effect": "Allow",
            "Action": [
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:GetRole",
                "iam:PassRole",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:GetRolePolicy",
                "iam:TagRole",
                "iam:UntagRole",
                "iam:CreateServiceLinkedRole"
            ],
            "Resource": "*"
        },
        {
            "Sid": "Lambda",
            "Effect": "Allow",
            "Action": [
                "lambda:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "StepFunctions",
            "Effect": "Allow",
            "Action": [
                "states:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ECS",
            "Effect": "Allow",
            "Action": [
                "ecs:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "Logs",
            "Effect": "Allow",
            "Action": [
                "logs:*"
            ],
            "Resource": "*"
        },
        {
            "Sid": "STS",
            "Effect": "Allow",
            "Action": [
                "sts:GetCallerIdentity",
                "sts:GetServiceBearerToken"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)

# Check if role exists
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo "Updating existing role: $ROLE_NAME"
    aws iam update-assume-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-document "$TRUST_POLICY"
else
    echo "Creating new role: $ROLE_NAME"
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "Role for GitHub Actions CI/CD for ${GITHUB_ORG}/${GITHUB_REPO}"
fi

# Update inline policy
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "GitHubActionsDeployPolicy" \
    --policy-document "$PERMISSIONS_POLICY"

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Setup Complete!                                             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Role ARN: $ROLE_ARN"
echo ""
echo "Add this to your GitHub repository secrets:"
echo "  AWS_DEPLOY_ROLE_ARN = $ROLE_ARN"
echo ""
echo "Or run:"
echo "  gh secret set AWS_DEPLOY_ROLE_ARN --repo ${GITHUB_ORG}/${GITHUB_REPO} --body '$ROLE_ARN'"
