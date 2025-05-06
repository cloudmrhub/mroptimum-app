#!/bin/bash

# === MR Optimum System Test Script ===

set -e

echo "Starting test script for MRORootStack..."
STACK_NAME="MRORootStack"

echo "Fetching CloudFormation outputs for $STACK_NAME..."
OUTPUTS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs" --output json)

# Extract key outputs
RunJobFunctionArn=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="RunJobFunctionArn") | .OutputValue')
UpdateJobFunctionArn=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="UpdateJobFunctionArn") | .OutputValue')
PipelineCompletedApi=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="PipelineCompletedApi") | .OutputValue')
StateMachineArn=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="StateMachineArn") | .OutputValue')
ResultsBucket=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="ResultsBucket") | .OutputValue')

# Create test payload file for Lambda
echo '{"job_id": "123", "input": "test-sequence"}' > test_payload.json

# === Test Step Function Execution ===
EXECUTION_NAME="test-run-$(date +%s)"
echo " Starting Step Function execution: $EXECUTION_NAME"
aws stepfunctions start-execution \
  --state-machine-arn "$StateMachineArn" \
  --name "$EXECUTION_NAME" \
  --input file://test_payload.json

# === Test RunJob Lambda Function ===
aws lambda invoke \
  --function-name "$RunJobFunctionArn" \
  --payload file://test_payload.json \
  --cli-binary-format raw-in-base64-out \
  output-runjob.json

# === Test UpdateJob Lambda Function ===
aws lambda invoke \
  --function-name "$UpdateJobFunctionArn" \
  --payload file://update_payload.json \
  --cli-binary-format raw-in-base64-out \
  output-updatejob.json

# === Test API Gateway Endpoint ===
echo "Testing API Gateway endpoint..."
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"job_id": "abc123"}' \
  "https://$PipelineCompletedApi"

# === Test S3 Upload ===
TEST_FILE="testfile-$(date +%s).txt"
echo "📦 Uploading test file to S3: $TEST_FILE"
echo "Hello from MR Optimum test" > "$TEST_FILE"
aws s3 cp "$TEST_FILE" "s3://$ResultsBucket/$TEST_FILE"

echo "Test script completed successfully."
