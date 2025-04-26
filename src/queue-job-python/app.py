import boto3
import os
import json
import traceback

STATE_MACHINE_ARN = os.environ.get("STATE_MACHINE_ARN", "arn:aws:states:us-east-1:879381258545:stateMachine:JobStateMachine-dev")

sfn = boto3.client('stepfunctions')

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event)}")

    try:
        response = sfn.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            input=json.dumps(event)
        )

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "*",
                "Access-Control-Allow-Methods": "OPTIONS,POST"
            },
            "body": json.dumps({
                "message": "Step Function started",
                "executionArn": response["executionArn"]
            })
        }

    except Exception as e:
        print("Full error:", traceback.format_exc())

        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "*",
                "Access-Control-Allow-Methods": "OPTIONS,POST"
            },
            "body": json.dumps({
                "message": f"Step Function execution failed: {str(e)}"
            }),
            "isBase64Encoded": False
        }
    