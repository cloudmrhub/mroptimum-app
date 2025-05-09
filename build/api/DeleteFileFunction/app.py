import json
import boto3
import os
import requests

def lambda_handler(event, context):
    try:
        body = json.loads(event['body'])
        s3 = boto3.client('s3')
        bucket = os.environ['DataBucketName']
        key = body['key']

        # Delete object from S3
        s3.delete_object(Bucket=bucket, Key=key)

        # Notify Cortex that data has been deleted
        requests.post(
            os.environ['deleteDataAPI'],
            headers={
                'Content-Type': 'application/json',
                'Authorization': event['headers'].get('Authorization', '')
            },
            json={"key": key}
        )

        return {
            "statusCode": 200,
            "body": json.dumps({"message": "File deleted successfully"})
        }

    except Exception as e:
        print("Error:", e)
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
