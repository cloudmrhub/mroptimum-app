#!/bin/bash
#
# Create ECR repositories for MR Optimum
#
# This script creates both private and public ECR repositories
# for storing Docker images used in Mode 1 and Mode 2.
#

set -e

AWS_REGION="${AWS_REGION:-us-east-1}"
PRIVATE_REPO_PREFIX="mroptimum"
PUBLIC_REPO_PREFIX="cloudmrhub/mroptimum"

echo "Creating ECR repositories in region: $AWS_REGION"
echo ""

# Create private repositories
echo "Creating private ECR repositories..."
for suffix in "lambda" "fargate"; do
    REPO_NAME="${PRIVATE_REPO_PREFIX}-${suffix}"
    if aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$AWS_REGION" &>/dev/null; then
        echo "  ✓ $REPO_NAME already exists"
    else
        aws ecr create-repository \
            --repository-name "$REPO_NAME" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true \
            --image-tag-mutability MUTABLE
        echo "  ✓ Created $REPO_NAME"
    fi
done

# Create public repositories (requires us-east-1)
echo ""
echo "Creating public ECR repositories..."
for suffix in "lambda" "fargate"; do
    REPO_NAME="${PUBLIC_REPO_PREFIX}-${suffix}"
    
    # Check if exists
    if aws ecr-public describe-repositories --repository-names "$REPO_NAME" --region us-east-1 &>/dev/null; then
        echo "  ✓ $REPO_NAME already exists"
    else
        aws ecr-public create-repository \
            --repository-name "$REPO_NAME" \
            --region us-east-1 \
            --catalog-data '{
                "description": "MR Optimum '"$suffix"' image for Mode 2 deployments",
                "architectures": ["x86_64"],
                "operatingSystems": ["Linux"]
            }'
        echo "  ✓ Created public.ecr.aws/$REPO_NAME"
    fi
done

echo ""
echo "ECR repositories created successfully!"
echo ""
echo "Private repositories (for Mode 1):"
aws ecr describe-repositories --query "repositories[?starts_with(repositoryName, '${PRIVATE_REPO_PREFIX}')].repositoryUri" --output table --region "$AWS_REGION"
echo ""
echo "Public repositories (for Mode 2 users):"
echo "  public.ecr.aws/${PUBLIC_REPO_PREFIX}-lambda"
echo "  public.ecr.aws/${PUBLIC_REPO_PREFIX}-fargate"
