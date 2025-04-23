import json
import os
import boto3

s3 = boto3.client('s3')
FAILED_BUCKET = os.environ['FAILED_BUCKET']

def lambda_handler(event, context):
    print("Received event:", event)
    
    job_id = event.get("job_id", "unknown-job")
    data = json.dumps(event).encode("utf-8")
    
    s3.put_object(
        Bucket=FAILED_BUCKET,
        Key=f"{job_id}-failed.json",
        Body=data
    )

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Failure archived."})
    }