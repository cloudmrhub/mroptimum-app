import os
import json
import boto3
import requests
import zipfile
import uuid

# Disable SSL verification (if needed for requests)
os.environ['CURL_CA_BUNDLE'] = ''

# Environment variables injected by CloudFormation
PIPELINE_COMPLETED_API = os.getenv("PipelineCompleted")
PIPELINE_FAILED_API = os.getenv("PipelineFailed")
PIPELINE_SCHEDULE_API = os.getenv("PipelineScheduler")
RESULTS_BUCKET = os.getenv("ResultsBucketName", "mroptimum-result")
FAILED_BUCKET = os.getenv("FailedBucketName", "mroptimum-failed")
HOST = os.getenv("Host", "")

def get_headers():
    return {
        "Content-Type": "application/json",
        "User-Agent": "MR-Optimum-UpdateJob/1.0",
        "From": "support@mroptimum.com",
        "Host": HOST
    }

def get_headers_with_token(token):
    headers = get_headers()
    headers["Authorization"] = token
    return headers

def lambda_handler(event, context):
    s3_client = boto3.client("s3")
    s3_resource = boto3.resource("s3")
    
    # Extract bucket and object info from event
    try:
        bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
        file_key = event["Records"][0]["s3"]["object"]["key"]
    except (KeyError, IndexError) as e:
        print("Malformed S3 Event:", event)
        return {"statusCode": 400, "body": json.dumps({"error": "Malformed S3 event"})}

    # Download the ZIP file to /tmp
    local_zip_path = f"/tmp/{uuid.uuid4()}.zip"
    s3_resource.Bucket(bucket_name).download_file(file_key, local_zip_path)

    # Extract info.json
    try:
        with zipfile.ZipFile(local_zip_path, 'r') as archive:
            info_json = json.loads(archive.read('info.json'))
    except Exception as e:
        print("Failed to read info.json from archive:", str(e))
        return {"statusCode": 500, "body": json.dumps({"error": "Failed to read info.json"})}

    token = info_json.get("headers", {}).get("options", {}).get("token")
    pipeline_id = info_json.get("headers", {}).get("options", {}).get("pipelineid")
    alias = info_json.get("headers", {}).get("options", {}).get("alias")

    if not token:
        print("Missing token in info.json")
        return {"statusCode": 400, "body": json.dumps({"error": "Missing token in info.json"})}

    if not pipeline_id and alias:
        # No pipeline ID, try to create a new pipeline schedule
        try:
            payload = {"application": "MR Optimum", "alias": alias}
            response = requests.post(
                PIPELINE_SCHEDULE_API,
                data=json.dumps(payload),
                headers=get_headers_with_token(token),
                timeout=10
            )
            response.raise_for_status()
            pipeline_id = response.json().get("pipeline")
        except Exception as e:
            print("Failed to schedule pipeline:", str(e))
            return {"statusCode": 500, "body": json.dumps({"error": "Failed to schedule pipeline"})}

    if not pipeline_id:
        print("Pipeline ID could not be determined.")
        return {"statusCode": 400, "body": json.dumps({"error": "Pipeline ID missing and could not be created."})}

    # Prepare result payload
    payload = {
        "results": f"s3://{bucket_name}/{file_key}",
        "output": f"s3://{bucket_name}/{file_key}",
        "log": "None",
        "options": "None",
        "input": "None"
    }

    # Choose correct API based on bucket
    try:
        if bucket_name == RESULTS_BUCKET:
            url = f"{PIPELINE_COMPLETED_API}/{pipeline_id}"
        elif bucket_name == FAILED_BUCKET:
            url = f"{PIPELINE_FAILED_API}/{pipeline_id}"
        else:
            print(f"Unknown bucket: {bucket_name}")
            return {"statusCode": 400, "body": json.dumps({"error": "Unknown bucket"})}

        result = requests.post(
            url,
            data=json.dumps(payload),
            headers=get_headers_with_token(token),
            timeout=10
        )
        result.raise_for_status()

        return {"statusCode": 200, "body": json.dumps({"message": "Pipeline updated successfully."})}

    except Exception as e:
        print("Error updating pipeline:", str(e))
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
