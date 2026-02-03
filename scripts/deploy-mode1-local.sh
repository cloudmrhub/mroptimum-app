#!/bin/bash
#
# Deploy Mode 1 Stack Locally
# This replicates what the CI/CD pipeline does
#
# ═══════════════════════════════════════════════════════════════════════════════
# ENVIRONMENT VARIABLES
# ═══════════════════════════════════════════════════════════════════════════════
#
# Required for CI/CD (non-interactive mode):
#   VPC_ID              - VPC ID for ECS tasks (e.g., vpc-023cde8a4c93e9d12)
#   SUBNET_ID_1         - First subnet ID (e.g., subnet-0a2008dc8f305421f)
#   SUBNET_ID_2         - Second subnet ID (e.g., subnet-0b5d882b93cc6ff2e)
#   SECURITY_GROUP_ID   - Security group ID (e.g., sg-0cb8fdbe5efef42d1)
#   CLOUDMR_API_URL     - CloudMR Brain API URL (e.g., https://api.cloudmrhub.com)
#   CLOUDMR_ADMIN_TOKEN - Admin token for computing unit registration
#
# Optional (have defaults):
#   AWS_PROFILE         - AWS CLI profile (default: nyu, ignored in CI)
#   AWS_REGION          - AWS region (default: us-east-1)
#   STACK_NAME          - CloudFormation stack name (default: mroptimum-app-test)
#   CLOUDMR_BRAIN_STACK - CloudMR Brain stack name (default: py-cloudmr-brain)
#
# CI Detection:
#   The script auto-detects CI mode via GITHUB_ACTIONS or CI environment variables.
#   In CI mode, all "Required for CI/CD" variables must be set (no interactive prompts).
#
# ═══════════════════════════════════════════════════════════════════════════════


set -e

AWS_PROFILE="${AWS_PROFILE:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_NAME:-mroptimum-app-test}"
CLOUDMR_BRAIN_STACK="${CLOUDMR_BRAIN_STACK:-cloudmrhub-brain}"

# CI mode detection (non-interactive if these are set)
CI_MODE="${CI:-false}"
if [ -n "$GITHUB_ACTIONS" ]; then
    CI_MODE="true"
fi

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Deploy MR Optimum Mode 1 Stack                              ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Build AWS CLI profile arg
AWS_ARGS=""
if [ -n "$AWS_PROFILE" ]; then
    AWS_ARGS="--profile $AWS_PROFILE"
fi

# Get AWS account
ACCOUNT_ID=$(aws sts get-caller-identity $AWS_ARGS --query Account --output text)
echo "Account:     $ACCOUNT_ID"
echo "Profile:     ${AWS_PROFILE:-default}"
echo "Region:      $AWS_REGION"
echo "Stack Name:  $STACK_NAME"
echo "CI Mode:     $CI_MODE"
echo ""

# Get image URIs
PRIVATE_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
LAMBDA_IMAGE_URI="${PRIVATE_REGISTRY}/mroptimum-lambda:latest"
FARGATE_IMAGE_URI="${PRIVATE_REGISTRY}/mroptimum-fargate:latest"

echo "Lambda Image:  $LAMBDA_IMAGE_URI"
echo "Fargate Image: $FARGATE_IMAGE_URI"
echo ""

# Check images exist
echo "Checking if images exist in ECR..."
if ! aws ecr describe-images \
    --repository-name mroptimum-lambda \
    --image-ids imageTag=latest \
    $AWS_ARGS \
    --region "$AWS_REGION" &>/dev/null; then
    echo "❌ Lambda image not found in ECR. Run ./scripts/build-and-push-local.sh first"
    exit 1
fi

if ! aws ecr describe-images \
    --repository-name mroptimum-fargate \
    --image-ids imageTag=latest \
    $AWS_ARGS \
    --region "$AWS_REGION" &>/dev/null; then
    echo "❌ Fargate image not found in ECR. Run ./scripts/build-and-push-local.sh first"
    exit 1
fi
echo "✓ Images found"
echo ""

# Get networking parameters
echo "Getting networking parameters..."

# VPC - use env var or prompt
VPC_ID="${VPC_ID:-}"
if [ -z "$VPC_ID" ]; then
    DEFAULT_VPC=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        $AWS_ARGS \
        --region "$AWS_REGION" \
        --query "Vpcs[0].VpcId" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$DEFAULT_VPC" ] || [ "$DEFAULT_VPC" = "None" ]; then
        if [ "$CI_MODE" = "true" ]; then
            echo "❌ No default VPC and VPC_ID not set. Set VPC_ID env var."
            exit 1
        fi
        echo "No default VPC found. Available VPCs:"
        aws ec2 describe-vpcs \
            $AWS_ARGS \
            --region "$AWS_REGION" \
            --query "Vpcs[*].[VpcId,Tags[?Key=='Name'].Value|[0]||'(no name)',IsDefault]" \
            --output table
        echo ""
        read -p "Enter VPC ID (e.g. vpc-xxxxx): " VPC_ID
        if [ -z "$VPC_ID" ]; then
            VPC_ID=$(aws ec2 describe-vpcs \
                --filters "Name=tag:Name,Values=cloudmrhub-vpc" \
                $AWS_ARGS \
                --region "$AWS_REGION" \
                --query "Vpcs[0].VpcId" \
                --output text 2>/dev/null || echo "")
        fi
    else
        VPC_ID="$DEFAULT_VPC"
    fi
fi
echo "VPC: $VPC_ID"

# Subnets - use env vars or auto-detect
SUBNET_ID_1="${SUBNET_ID_1:-}"
SUBNET_ID_2="${SUBNET_ID_2:-}"

if [ -z "$SUBNET_ID_1" ] || [ -z "$SUBNET_ID_2" ]; then
    SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
        $AWS_ARGS \
        --region "$AWS_REGION" \
        --query "Subnets[*].SubnetId" \
        --output text 2>/dev/null || echo "")
    
    SUBNET_ARRAY=($SUBNETS)
    
    if [ ${#SUBNET_ARRAY[@]} -lt 2 ]; then
        # Try all subnets
        SUBNETS=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            $AWS_ARGS \
            --region "$AWS_REGION" \
            --query "Subnets[*].SubnetId" \
            --output text)
        SUBNET_ARRAY=($SUBNETS)
    fi
    
    if [ ${#SUBNET_ARRAY[@]} -lt 2 ]; then
        if [ "$CI_MODE" = "true" ]; then
            echo "❌ Need 2 subnets. Set SUBNET_ID_1 and SUBNET_ID_2 env vars."
            exit 1
        fi
        echo "Available subnets:"
        aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
            $AWS_ARGS --region "$AWS_REGION" \
            --query "Subnets[*].[SubnetId,AvailabilityZone]" --output table
        read -p "Subnet 1 ID: " SUBNET_ID_1
        read -p "Subnet 2 ID: " SUBNET_ID_2
    else
        SUBNET_ID_1="${SUBNET_ID_1:-${SUBNET_ARRAY[0]}}"
        SUBNET_ID_2="${SUBNET_ID_2:-${SUBNET_ARRAY[1]}}"
    fi
fi

# Security Group - use env var or create
SG_ID="${SECURITY_GROUP_ID:-}"
if [ -z "$SG_ID" ]; then
    SG_NAME="mroptimum-ecs-sg"
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
        $AWS_ARGS \
        --region "$AWS_REGION" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
        echo "Creating security group..."
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SG_NAME" \
            --description "Security group for MR Optimum ECS tasks" \
            --vpc-id "$VPC_ID" \
            $AWS_ARGS \
            --region "$AWS_REGION" \
            --query "GroupId" \
            --output text)
        
        aws ec2 authorize-security-group-egress \
            --group-id "$SG_ID" \
            --protocol -1 \
            --cidr 0.0.0.0/0 \
            $AWS_ARGS \
            --region "$AWS_REGION" 2>/dev/null || true
    fi
fi

echo "Subnet 1:  $SUBNET_ID_1"
echo "Subnet 2:  $SUBNET_ID_2"
echo "Sec Group: $SG_ID"
echo ""

# CloudMR API URL
CLOUDMR_API_URL="${CLOUDMR_API_URL:-}"
if [ -z "$CLOUDMR_API_URL" ]; then
    if [ "$CI_MODE" = "true" ]; then
        CLOUDMR_API_URL="https://api.cloudmrhub.com"
    else
        read -p "CloudMR Brain API URL [https://api.cloudmrhub.com]: " CLOUDMR_API_URL
        CLOUDMR_API_URL="${CLOUDMR_API_URL:-https://api.cloudmrhub.com}"
    fi
fi

CLOUDMR_HOST=$(echo "$CLOUDMR_API_URL" | sed 's|https://||' | sed 's|http://||' | sed 's|/.*||')

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Deploying SAM stack..."
echo ""

sam deploy \
    --template-file template.yaml \
    $AWS_ARGS \
    --region "$AWS_REGION" \
    --stack-name "$STACK_NAME" \
    --parameter-overrides \
        LambdaImageUri="$LAMBDA_IMAGE_URI" \
        FargateImageUri="$FARGATE_IMAGE_URI" \
        CortexHost="$CLOUDMR_HOST" \
        CloudMRBrainStackName="$CLOUDMR_BRAIN_STACK" \
        ECSClusterName="${STACK_NAME}-cluster" \
        SubnetId1="$SUBNET_ID_1" \
        SubnetId2="$SUBNET_ID_2" \
        SecurityGroupIds="$SG_ID" \
        StageName="${STAGE_NAME:-Prod}" \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --no-confirm-changeset

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Deployment Complete!                                        ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Get outputs
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    $AWS_ARGS \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CalculationStateMachineArn`].OutputValue' \
    --output text)

echo "State Machine ARN: $STATE_MACHINE_ARN"

# Get bucket names
DATA_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$CLOUDMR_BRAIN_STACK" \
    $AWS_ARGS --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`DataBucketName`].OutputValue' \
    --output text 2>/dev/null || echo "")

RESULTS_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$CLOUDMR_BRAIN_STACK" \
    $AWS_ARGS --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ResultsBucketName`].OutputValue' \
    --output text 2>/dev/null || echo "")

FAILED_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$CLOUDMR_BRAIN_STACK" \
    $AWS_ARGS --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`FailedBucketName`].OutputValue' \
    --output text 2>/dev/null || echo "")

# Auto-registration
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Registering computing unit with CloudMR Brain..."

ADMIN_TOKEN="${CLOUDMR_ADMIN_TOKEN:-}"
if [ -z "$ADMIN_TOKEN" ] && [ "$CI_MODE" != "true" ]; then
    read -sp "CloudMR Admin Token (for registration): " ADMIN_TOKEN
    echo ""
fi

if [ -n "$ADMIN_TOKEN" ]; then
    REGISTER_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${CLOUDMR_API_URL}/api/computing-unit/register" \
        -H "Authorization: Bearer $ADMIN_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"appName\": \"mroptimum\",
            \"mode\": \"mode1\",
            \"provider\": \"cloudmrhub\",
            \"awsAccountId\": \"$ACCOUNT_ID\",
            \"region\": \"$AWS_REGION\",
            \"stateMachineArn\": \"$STATE_MACHINE_ARN\",
            \"resultsBucket\": \"$RESULTS_BUCKET\",
            \"failedBucket\": \"$FAILED_BUCKET\",
            \"dataBucket\": \"$DATA_BUCKET\",
            \"isDefault\": true
        }")
    
    HTTP_CODE=$(echo "$REGISTER_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$REGISTER_RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        echo "✓ Computing unit registered successfully!"
        echo "$RESPONSE_BODY"
    else
        echo "❌ Registration failed (HTTP $HTTP_CODE)"
        echo "$RESPONSE_BODY"
        exit 1
    fi
else
    echo "⚠ No admin token provided. Skipping registration."
fi

echo ""
echo "Done!"