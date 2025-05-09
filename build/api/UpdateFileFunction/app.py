import json
import os
import requests

def lambda_handler(event, context):
    try:
        body = json.loads(event['body'])

        payload = {
            "key": body["key"],
            "filename": body["filename"]
        }

        # Send update request to Cortex
        response = requests.post(
            os.environ["updateDataAPI"],
            headers={
                "Content-Type": "application/json",
                "Authorization": event["headers"].get("Authorization", "")
            },
            json=payload
        )

        if response.status_code != 200:
            raise Exception("Cortex update failed with status " + str(response.status_code))

        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Metadata updated successfully"})
        }

    except Exception as e:
        print("Error:", e)
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
