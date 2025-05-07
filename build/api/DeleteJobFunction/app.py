import json
import os
import requests

os.environ['CURL_CA_BUNDLE'] = ''

def fix_cors(response):
    response['headers'] = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': '*',
        'Access-Control-Allow-Methods': '*'
    }
    return response

def get_headers():
    return {
        "Content-Type": "application/json",
        "User-Agent": "My User Agent 1.0",
        "From": "theweblogin@iam.com"
    }

def get_headers_with_token(token):
    headers = get_headers()
    headers["Authorization"] = token
    return headers

def lambda_handler(event, context):
    try:
        headers = event.get('headers', {})
        authorization_header = headers.get('Authorization', '')

        body = json.loads(event.get('body', '{}'))
        alias = body["alias"]
        task = body.get("task", "")
        application = "MR Optimum"

        pipeline_api = os.environ.get("PipelineScheduler")
        if not pipeline_api:
            return fix_cors({
                "statusCode": 500,
                "body": json.dumps({"error": "Missing PipelineScheduler environment variable"})
            })

        payload = {
            "application": application,
            "alias": alias,
            "task": task
        }

        response = requests.delete(
            pipeline_api,
            data=json.dumps(payload),
            headers=get_headers_with_token(authorization_header)
        )

        return fix_cors({
            "statusCode": response.status_code,
            "body": response.text
        })

    except Exception as e:
        return fix_cors({
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        })
