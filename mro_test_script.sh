#!/bin/bash
set -e

echo "Starting test script for MRORootStack..."

# Fetch ARNs from nested stacks
UPDATE_JOB_ARN=$(aws cloudformation describe-stacks \
  --stack-name MRORootStack-ComputeStack-18KSJ9M95ZSNM \
  --query "Stacks[0].Outputs[?OutputKey=='UpdateJobFunctionArn'].OutputValue" \
  --output text)

RUN_JOB_ARN=$(aws cloudformation describe-stacks \
  --stack-name MRORootStack-ComputeStack-18KSJ9M95ZSNM \
  --query "Stacks[0].Outputs[?OutputKey=='RunJobFunctionArn'].OutputValue" \
  --output text)

RESULTS_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name MRORootStack-CommonStack-182S7TJ5H9RJ0 \
  --query "Stacks[0].Outputs[?OutputKey=='ResultsBucket'].OutputValue" \
  --output text)

FAILED_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name MRORootStack-CommonStack-182S7TJ5H9RJ0 \
  --query "Stacks[0].Outputs[?OutputKey=='FailedBucket'].OutputValue" \
  --output text)

STEP_FUNCTION_ARN="arn:aws:states:us-east-1:879381258545:stateMachine:JobStateMachine-dev"

echo "Testing Step Function execution..."
EXECUTION_ARN=$(aws stepfunctions start-execution \
  --state-machine-arn "$STEP_FUNCTION_ARN" \
  --input "{\"bucket\": \"$RESULTS_BUCKET\", \"key\": \"sample-job-input.json\"}" \
  --query "executionArn" --output text)

echo "Started execution: $EXECUTION_ARN"
echo "Polling for execution status..."

while true; do
  STATUS=$(aws stepfunctions describe-execution \
    --execution-arn "$EXECUTION_ARN" \
    --query "status" \
    --output text)
  
  echo "Current status: $STATUS"
  if [[ "$STATUS" == "SUCCEEDED" || "$STATUS" == "FAILED" || "$STATUS" == "TIMED_OUT" || "$STATUS" == "ABORTED" ]]; then
    break
  fi
  sleep 5
done

if [[ "$STATUS" == "SUCCEEDED" ]]; then
  echo "✅ Execution succeeded!"
else
  echo "❌ Execution failed with status: $STATUS"
fi

echo "Execution output:"
aws stepfunctions describe-execution --execution-arn "$EXECUTION_ARN"
