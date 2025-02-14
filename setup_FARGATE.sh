#!/bin/bash
set -e

# ---------------------------
# Configuration Variables
# ---------------------------
REGION="us-east-1"
REPO_NAME="mroptimum-processor"
CODEBUILD_PROJECT="mroptimum-processor-build"
SOURCE_DIR="fargate/cluster/run-job-python-mroptimum-fg"
ZIP_FILE="run-job-python-FG.zip"
RESULTS_BUCKET="mrorv2"
FAILED_BUCKET="mrofv2"
# ---------------------------
# Clean Existing ECR Repository
# ---------------------------
clean_ecr_repository() {
    echo "Checking for existing ECR repository..."
    if aws ecr describe-repositories --repository-names $REPO_NAME --region $REGION &>/dev/null; then
        echo "Found existing repository. Deleting..."
        aws ecr delete-repository \
            --repository-name $REPO_NAME \
            --region $REGION \
            --force
        sleep 30  # Wait for complete deletion
    fi
}

# ---------------------------
# Prepare Docker Source Code
# ---------------------------
prepare_docker_source() {
    echo "Zipping Docker source code..."
    rm -f $ZIP_FILE
    zip -r $ZIP_FILE $SOURCE_DIR -x "*/__pycache__/*"
    
    echo "Uploading source to S3..."
    aws s3 cp $ZIP_FILE s3://source-docker-mroptimum/$ZIP_FILE
}

# ---------------------------
# Deploy Stack with Retry Logic
# ---------------------------
deploy_stack_with_retry() {
    local stack_name=$1
    local template=$2
    local params=${3:-}
    
    echo "Deploying stack: $stack_name"
    echo "Template: $template"
    echo "Parameters: $params"
    echo "Region: $REGION"
    

    for attempt in {1..3}; do
        echo "Deployment attempt $attempt/3"
        if aws cloudformation deploy \
            --stack-name $stack_name \
            --template-file $template \
            --capabilities CAPABILITY_IAM \
            --region $REGION \
            $params; then
            return 0
        fi
        
        echo "Waiting 30 seconds before retry..."
        sleep 30
    done
    
    echo "Failed to deploy after 3 attempts"
    return 1
}


# ---------------------------
# Wait for Stack Completion
# ---------------------------
wait_for_stack() {
    local stack_name=$1
    echo "Waiting for stack $stack_name to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name $stack_name \
        --region $REGION || \
    aws cloudformation wait stack-update-complete \
        --stack-name $stack_name \
        --region $REGION
}

# ---------------------------
# Build Docker Image with Logs
# ---------------------------
build_docker_image() {
    echo "Starting Docker image build..."
    BUILD_ID=$(aws codebuild start-build --project-name $CODEBUILD_PROJECT --query 'build.id' --output text)
    
    echo "Tracking build: $BUILD_ID"
    while true; do
        BUILD_INFO=$(aws codebuild batch-get-builds --ids $BUILD_ID --query 'builds[0]')
        STATUS=$(echo $BUILD_INFO | jq -r '.buildStatus')
        LOGS_URL=$(echo $BUILD_INFO | jq -r '.logs.deepLink')

        case $STATUS in
            "SUCCEEDED")
                echo "Build succeeded!"
                break
                ;;
            "FAILED"|"STOPPED")
                echo -e "\nBuild failed with status: $STATUS"
                echo "Debug logs: $LOGS_URL"
                
                # Get raw logs from CloudWatch
                LOG_STREAM=$(echo $BUILD_INFO | jq -r '.logs.groupName + "/" + .logs.streamName')
                echo -e "\nLast 100 log lines:"
                aws logs get-log-events \
                    --log-group-name $(echo $LOG_STREAM | cut -d'/' -f1) \
                    --log-stream-name $(echo $LOG_STREAM | cut -d'/' -f2) \
                    --limit 100 \
                    --region $REGION \
                    | jq -r '.events[].message'
                
                exit 1
                ;;
            *)
                echo -n "."
                sleep 30
                ;;
        esac
    done

    echo "Verifying ECR image..."
    ECR_URI=$(aws cloudformation describe-stacks \
        --stack-name mroptimum-cluster \
        --query 'Stacks[0].Outputs[?OutputKey==`ECRRepository`].OutputValue' \
        --output text)
        
    aws ecr describe-images \
        --repository-name $(basename $ECR_URI) \
        --image-ids imageTag=latest \
        --region $REGION
}

# ---------------------------
# Main Execution
# ---------------------------
clean_ecr_repository
prepare_docker_source

# Deploy VPC Stack
deploy_stack_with_retry "cmr-calculation00" "fargate/vpc/template.yaml"

# Deploy Cluster Stack
# deploy_stack_with_retry "mroptimum-cluster" "fargate/cluster/template.yaml" \
#     "--parameter-overrides \
#     VpcSubnets=$(aws cloudformation describe-stacks --stack-name cmr-calculation00 --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet1`].OutputValue' --output text),$(aws cloudformation describe-stacks --stack-name cmr-calculation00 --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet2`].OutputValue' --output text) \
#     VpcSecurityGroups=$(aws cloudformation describe-stacks --stack-name cmr-calculation00 --query 'Stacks[0].Outputs[?OutputKey==`ECSSecurityGroup`].OutputValue' --output text)"


deploy_stack_with_retry "mroptimum-cluster" "fargate/cluster/template.yaml" \
  "--parameter-overrides \
  VpcSubnets=$(aws cloudformation describe-stacks --stack-name cmr-calculation00 --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet1`].OutputValue' --output text),$(aws cloudformation describe-stacks --stack-name cmr-calculation00 --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnet2`].OutputValue' --output text) \
  VpcSecurityGroups=$(aws cloudformation describe-stacks --stack-name cmr-calculation00 --query 'Stacks[0].Outputs[?OutputKey==`ECSSecurityGroup`].OutputValue' --output text) \
  ResultsBucketName=${RESULTS_BUCKET} \
  FailedBucketName=${FAILED_BUCKET}"


# Add this wait after cluster deployment
wait_for_stack "mroptimum-cluster"

# Build and push Docker image
build_docker_image

echo "Deployment completed successfully!"
echo "ECR Image URI: $ECR_URI:latest"