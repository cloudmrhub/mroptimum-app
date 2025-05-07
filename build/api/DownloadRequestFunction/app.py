import json
import os
import boto3
import requests
from urllib.parse import urlparse

os.environ['CURL_CA_BUNDLE'] = ''

s3 = boto3.client("s3")
HOST = os.environ.get("Host")
URL_EXPIRATION = 3600  # 1 hour

def get_headers(auth_token):
    return {
        "Accept": "application/json",
        "Accept-Charset": "utf-8",
        "Accept-Encoding": "none",
        "Accept-Language": "en-US,en;q=0.8",
        "Connection": "keep-alive",
        "Content-Type": "application/json",
        "User-Agent": "curl",
        "From": "devn@cloudmrhub.com",
        "Authorization": auth_token,
        "Host": HOST
    }

def create_uploaded_file(name, address, created_at, updated_at):
    if not address:
        return {
            "id": 0,
            "link": "unknown",
            "createdAt": created_at,
            "updatedAt": updated_at,
            "status": "unavailable",
            "database": "s3",
            "fileName": name,
            "location": "-"
        }

    parsed = urlparse(address)
    parts = parsed.path.strip("/").split("/", 1)
    if len(parts) != 2:
        raise ValueError("Malformed S3 path")

    bucket, key = parts
    extension = os.path.splitext(key)[1].lstrip(".")

    url = s3.generate_presigned_url(
        "get_object",
        Params={
            "Bucket": bucket,
            "Key": key,
            "ResponseContentDisposition": f"attachment; filename={name}.{extension}"
        },
        ExpiresIn=URL_EXPIRATION
    )

    return {
        "id": 0,
        "link": url,
        "createdAt": created_at,
        "updatedAt": updated_at,
        "status": "available",
        "database": "s3",
        "fileName": name,
        "location": json.dumps({"Bucket": bucket, "Key": key})
    }

def lambda_handler(event, context):
    try:
        auth_header = event.get("headers", {}).get("Authorization", "")
        headers = get_headers(auth_header)

        resp = requests.get(f"https://{HOST}/api/pipeline/list/1", headers=headers)
        resp.raise_for_status()
        pipelines = resp.json()

        jobs = []
        for pipeline in pipelines[0]:
            alias = pipeline["alias"].replace(" ", "")
            created = pipeline["created_at"]
            updated = pipeline["updated_at"]

            jobs.append({
                "id": pipeline["id"],
                "alias": pipeline["alias"],
                "status": pipeline["status"],
                "createdAt": created,
                "updatedAt": updated,
                "setup": None,
                "pipeline_id": pipeline["pipeline"],
                "files": [
                    create_uploaded_file(f"{pipeline['alias']}_results", pipeline["results"], created, updated),
                    create_uploaded_file(f"{alias}_output", pipeline["output"], created, updated)
                ]
            })

        return {
            "statusCode": 200,
            "headers": {"Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"jobs": jobs})
        }

    except Exception as e:
        return {
            "statusCode": 403,
            "headers": {"Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"error": str(e)})
        }
