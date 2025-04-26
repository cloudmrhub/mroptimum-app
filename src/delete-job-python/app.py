import json
import os
import traceback

def lambda_handler(event, context):
    try:
        print("Delete job event received:", event)

        # You can add actual logic here to delete from S3, DynamoDB, etc.
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "*",
                "Access-Control-Allow-Methods": "OPTIONS,DELETE"
            },
            "body": json.dumps({
                "message": "Job deleted successfully."
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
                "Access-Control-Allow-Methods": "OPTIONS,DELETE"
            },
            "body": json.dumps({
                "message": f"Delete job failed: {str(e)}"
            }),
            "isBase64Encoded": False
        }

