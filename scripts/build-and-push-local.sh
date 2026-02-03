#!/bin/bash
#
# Build and Push Docker Images Locally
# This replicates what the CI/CD pipeline does
#

set -e

AWS_PROFILE="${AWS_PROFILE:-nyu}"
AWS_REGION="${AWS_REGION:-us-east-1}"
IMAGE_TAG="${IMAGE_TAG:-local-$(date +%Y%m%d-%H%M%S)}"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Build and Push Docker Images (Mode 1)                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Profile:   $AWS_PROFILE"
echo "Region:    $AWS_REGION"
echo "Image Tag: $IMAGE_TAG"
echo ""

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
echo "Account: $ACCOUNT_ID"
echo ""

# ECR repository names
PRIVATE_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
LAMBDA_REPO="mroptimum-lambda"
FARGATE_REPO="mroptimum-fargate"

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --profile "$AWS_PROFILE" --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$PRIVATE_REGISTRY"

cd calculation/src

# Build Lambda image
echo ""
echo "Building Lambda image..."
docker build --provenance=false -f DockerfileLambda -t "${LAMBDA_REPO}:${IMAGE_TAG}" .
docker tag "${LAMBDA_REPO}:${IMAGE_TAG}" "${LAMBDA_REPO}:latest"

# Build Fargate image
echo ""
echo "Building Fargate image..."
docker build --provenance=false -f DockerfileFargate -t "${FARGATE_REPO}:${IMAGE_TAG}" .
docker tag "${FARGATE_REPO}:${IMAGE_TAG}" "${FARGATE_REPO}:latest"
cd ../../

# Tag for ECR
LAMBDA_URI="${PRIVATE_REGISTRY}/${LAMBDA_REPO}"
FARGATE_URI="${PRIVATE_REGISTRY}/${FARGATE_REPO}"

docker tag "${LAMBDA_REPO}:${IMAGE_TAG}" "${LAMBDA_URI}:${IMAGE_TAG}"
docker tag "${LAMBDA_REPO}:latest" "${LAMBDA_URI}:latest"
docker tag "${FARGATE_REPO}:${IMAGE_TAG}" "${FARGATE_URI}:${IMAGE_TAG}"
docker tag "${FARGATE_REPO}:latest" "${FARGATE_URI}:latest"

# Push to ECR
echo ""
echo "Pushing Lambda image to ECR..."
docker push "${LAMBDA_URI}:${IMAGE_TAG}"
docker push "${LAMBDA_URI}:latest"

echo ""
echo "Pushing Fargate image to ECR..."
docker push "${FARGATE_URI}:${IMAGE_TAG}"
docker push "${FARGATE_URI}:latest"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Images built and pushed successfully!                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "Lambda URI:  ${LAMBDA_URI}:latest"
echo "Fargate URI: ${FARGATE_URI}:latest"
echo ""
echo "To deploy, set these as parameters:"
echo "  LambdaImageUri=${LAMBDA_URI}:latest"
echo "  FargateImageUri=${FARGATE_URI}:latest"
