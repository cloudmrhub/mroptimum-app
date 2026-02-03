#!/bin/bash
#
# Test Job Execution
# Invokes the Step Functions state machine with a test payload
#

set -e

AWS_PROFILE="${AWS_PROFILE:-nyu}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STATE_MACHINE_ARN="${1}"

if [ -z "$STATE_MACHINE_ARN" ]; then
    echo "Usage: $0 <state-machine-arn>"
    echo ""
    echo "Get the ARN from stack outputs:"
    echo "  aws cloudformation describe-stacks --stack-name mroptimum-app-test --query 'Stacks[0].Outputs[?OutputKey==\`CalculationStateMachineArn\`].OutputValue' --output text"
    exit 1
fi

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║   Test MR Optimum Job Execution                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "State Machine: $STATE_MACHINE_ARN"
echo "Profile:       $AWS_PROFILE"
echo "Region:        $AWS_REGION"
echo ""

# Create test payload (use one of the example files)
TEST_FILE="calculation/event.json"
if [ ! -f "$TEST_FILE" ]; then
    echo "❌ Test file not found: $TEST_FILE"
    exit 1
fi

echo "Using test payload: $TEST_FILE"
echo ""

# Start execution
EXECUTION_NAME="test-$(date +%Y%m%d-%H%M%S)"
echo "Starting execution: $EXECUTION_NAME"

EXECUTION_ARN=$(aws stepfunctions start-execution \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --name "$EXECUTION_NAME" \
    --input "file://$TEST_FILE" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query "executionArn" \
    --output text)

echo "Execution ARN: $EXECUTION_ARN"
echo ""

# Monitor execution
echo "Monitoring execution (Ctrl+C to stop monitoring)..."
echo ""

while true; do
    STATUS=$(aws stepfunctions describe-execution \
        --execution-arn "$EXECUTION_ARN" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query "status" \
        --output text)
    
    if [ "$STATUS" = "RUNNING" ]; then
        echo -n "."
        sleep 5
    elif [ "$STATUS" = "SUCCEEDED" ]; then
        echo ""
        echo ""
        echo "✅ Execution SUCCEEDED!"
        
        # Get output
        OUTPUT=$(aws stepfunctions describe-execution \
            --execution-arn "$EXECUTION_ARN" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "output" \
            --output text)
        
        echo ""
        echo "Output:"
        echo "$OUTPUT" | jq . || echo "$OUTPUT"
        break
    elif [ "$STATUS" = "FAILED" ]; then
        echo ""
        echo ""
        echo "❌ Execution FAILED!"
        
        # Get error
        ERROR=$(aws stepfunctions describe-execution \
            --execution-arn "$EXECUTION_ARN" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query "{error: error, cause: cause}" \
            --output json)
        
        echo ""
        echo "Error details:"
        echo "$ERROR" | jq .
        exit 1
    else
        echo ""
        echo ""
        echo "⚠ Execution status: $STATUS"
        break
    fi
done

echo ""
echo "View execution in console:"
echo "https://${AWS_REGION}.console.aws.amazon.com/states/home?region=${AWS_REGION}#/executions/details/${EXECUTION_ARN}"
