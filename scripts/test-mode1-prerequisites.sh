#!/bin/bash
#
# Test Mode 1 Prerequisites
# Validates that your AWS account is ready for Mode 1 deployment
#

set -e

AWS_PROFILE="${AWS_PROFILE:-nyu}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLOUDMR_BRAIN_STACK="${CLOUDMR_BRAIN_STACK:-py-cloudmr-brain}"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   MR Optimum Mode 1 - Prerequisites Check                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Profile: $AWS_PROFILE"
echo "Region:  $AWS_REGION"
echo "CloudMR Brain Stack: $CLOUDMR_BRAIN_STACK"
echo ""

ERRORS=0

# Test 1: AWS CLI access
echo "✓ Checking AWS CLI access..."
if aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" --query Account --output text)
    echo "  ✓ AWS Account: $ACCOUNT_ID"
else
    echo "  ✗ AWS CLI not configured for profile $AWS_PROFILE"
    ERRORS=$((ERRORS + 1))
fi

# Test 2: CloudMR Brain stack exports
echo ""
echo "✓ Checking CloudMR Brain stack exports..."
for export_name in "DataBucketName" "ResultsBucketName" "FailedBucketName"; do
    EXPORT_KEY="${CLOUDMR_BRAIN_STACK}-${export_name}"
    VALUE=$(aws cloudformation list-exports \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "Exports[?Name=='$EXPORT_KEY'].Value" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$VALUE" ]; then
        echo "  ✓ $export_name: $VALUE"
    else
        echo "  ✗ Export not found: $EXPORT_KEY"
        ERRORS=$((ERRORS + 1))
    fi
done

# Test 3: ECR repositories
echo ""
echo "✓ Checking ECR repositories..."
for suffix in "lambda" "fargate"; do
    REPO_NAME="mroptimum-${suffix}"
    if aws ecr describe-repositories \
        --repository-names "$REPO_NAME" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" &>/dev/null; then
        URI=$(aws ecr describe-repositories \
            --repository-names "$REPO_NAME" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "repositories[0].repositoryUri" \
            --output text)
        echo "  ✓ $REPO_NAME: $URI"
    else
        echo "  ⚠ ECR repository not found: $REPO_NAME (will be created)"
    fi
done

# Test 4: VPC and networking
echo ""
echo "✓ Checking VPC and networking..."
DEFAULT_VPC=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query "Vpcs[0].VpcId" \
    --output text 2>/dev/null || echo "")

if [ -n "$DEFAULT_VPC" ] && [ "$DEFAULT_VPC" != "None" ]; then
    echo "  ✓ Default VPC: $DEFAULT_VPC"
    
    # Check for public subnets
    SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$DEFAULT_VPC" "Name=map-public-ip-on-launch,Values=true" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "Subnets[*].SubnetId" \
        --output text 2>/dev/null || echo "")
    
    SUBNET_COUNT=$(echo "$SUBNETS" | wc -w)
    if [ "$SUBNET_COUNT" -ge 2 ]; then
        echo "  ✓ Public subnets: $SUBNET_COUNT found"
    else
        echo "  ⚠ Only $SUBNET_COUNT public subnet(s) found (need 2 for high availability)"
    fi
else
    echo "  ⚠ No default VPC found"
fi

# Test 5: Docker
echo ""
echo "✓ Checking Docker..."
if command -v docker &>/dev/null; then
    if docker info &>/dev/null; then
        echo "  ✓ Docker is running"
    else
        echo "  ✗ Docker is installed but not running"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  ✗ Docker is not installed"
    ERRORS=$((ERRORS + 1))
fi

# Test 6: SAM CLI
echo ""
echo "✓ Checking SAM CLI..."
if command -v sam &>/dev/null; then
    SAM_VERSION=$(sam --version)
    echo "  ✓ SAM CLI: $SAM_VERSION"
else
    echo "  ⚠ SAM CLI not installed (optional for manual deployment)"
fi

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [ $ERRORS -eq 0 ]; then
    echo "✅ All critical checks passed! You're ready for Mode 1 deployment."
    echo ""
    echo "Next steps:"
    echo "  1. Create ECR repositories (if not exists):"
    echo "     ./scripts/create-ecr-repos.sh"
    echo ""
    echo "  2. Build and push Docker images:"
    echo "     ./scripts/build-and-push-local.sh"
    echo ""
    echo "  3. Deploy SAM stack:"
    echo "     ./scripts/deploy-mode1-local.sh"
    exit 0
else
    echo "❌ $ERRORS error(s) found. Please fix the issues above."
    exit 1
fi
