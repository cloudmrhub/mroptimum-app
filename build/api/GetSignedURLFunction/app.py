import json
import boto3
import os
import urllib.parse

def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
        bucket = body.get("bucket")
        key = body.get("key")
        operation = body.get("operation", "get_object")  # default to download
        expires_in = int(body.get("expires_in", 3600))   # default 1 hour

        if not bucket or not key:
            raise ValueError("Missing required fields: bucket and key")

        s3 = boto3.client("s3")
        url = s3.generate_presigned_url(
            ClientMethod=operation,
            Params={"Bucket": bucket, "Key": key},
            ExpiresIn=expires_in
        )

        return {
            "statusCode": 200,
            "body": json.dumps({"url": url}),
            "headers": {
                "Access-Control-Allow-Origin": "*"
            }
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)}),
            "headers": {
                "Access-Control-Allow-Origin": "*"
            }
        }
