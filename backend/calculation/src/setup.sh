#!/usr/bin/env bash
set -e

# 1) Set AWS region & account ID
AWS_REGION="us-east-1"
# ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --profile nyu)" 

# 2) ECR repo names (you can change these)
LAMBDA_REPO="mroptimum-run-job-lambda"
FARGATE_REPO="mroptimum-run-job-fargate"

# 3) Full ECR URIs
LAMBDA_IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${LAMBDA_REPO}:latest"
FARGATE_IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FARGATE_REPO}:latest"

echo "🔎 Using AWS Account: $ACCOUNT_ID, Region: $AWS_REGION"
echo "Lambda image URI:   $LAMBDA_IMAGE_URI"
echo "Fargate image URI:  $FARGATE_IMAGE_URI"

# 4) Ensure ECR repos exist (create them if they don’t)
for REPO in "${LAMBDA_REPO}" "${FARGATE_REPO}"; do
  # 1) Check if the repo exists
  if ! aws ecr describe-repositories --profile nyu \
        --repository-names "${REPO}" \
        --region "${AWS_REGION}" >/dev/null 2>&1; then
    # 2) If it does NOT exist, create it (ignore “AlreadyExists” on retry):
    aws ecr create-repository --profile nyu \
      --repository-name "${REPO}" \
      --region "${AWS_REGION}" \
    || echo "✅ ECR repository '${REPO}' already exists; skipping creation."
  else
    echo "✅ ECR repository '${REPO}' already exists; skipping creation."
  fi
done

echo "🔧 ECR repositories checked/created successfully."

# 5) Authenticate Docker to ECR
aws ecr get-login-password --region "${AWS_REGION}" --profile nyu\
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "✅ Docker authenticated to ECR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 6) Build & push the Fargate image (fargate-image stage in your Dockerfile)
echo "⏳ Building and pushing Fargate image…"
docker build --target fargate-image -t "${FARGATE_REPO}:latest"  -f Dockerfile .
docker tag "${FARGATE_REPO}:latest" "${FARGATE_IMAGE_URI}"
docker push "${FARGATE_IMAGE_URI}"
echo "✅ Fargate image pushed: ${FARGATE_IMAGE_URI}"


# 7) Build & push the Lambda image (lambda-image stage)
echo "⏳ Building and pushing Lambda image…"
docker build --target lambda-image \
  -t "${LAMBDA_REPO}:latest" \
  -f Dockerfile .
  

docker tag "${LAMBDA_REPO}:latest" "${LAMBDA_IMAGE_URI}"
docker push "${LAMBDA_IMAGE_URI}"
echo "✅ Lambda image pushed: ${LAMBDA_IMAGE_URI}"


# 8) Summarize
echo
echo "----------------------------------"
echo " Lambda Image URI:   ${LAMBDA_IMAGE_URI}"
echo " Fargate Image URI:  ${FARGATE_IMAGE_URI}"
echo "----------------------------------"
