import json
import boto3
import requests
import os

os.environ['CURL_CA_BUNDLE'] = ''

# Environment variables set in template.yaml
HOST = os.getenv('Host')
DELETE_DATA_API = os.getenv('deleteDataAPI')
UPDATE_DATA_API = os.getenv('updateDataAPI')
DATA_BUCKET = os.getenv('DataBucketName')


def get_headers_with_token(token):
    return {
        'Accept': '*/*',
        'Content-Type': 'application/json',
        'Authorization': token,
        'Host': HOST,
        'User-Agent': 'lambda',
    }


def fix_cors(response):
    response['headers'] = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': '*',
        'Access-Control-Allow-Methods': '*'
    }
    return response


def read_data(event, context):
    s3 = boto3.client('s3')
    try:
        headers = get_headers_with_token(event['headers']['Authorization'])
        response = requests.get(f'https://{HOST}/api/data', verify=False, headers=headers)
        response.raise_for_status()
        items = response.json()

        for item in items:
            if item.get('location', '').startswith('{'):
                loc = json.loads(item['location'])
                presigned_url = s3.generate_presigned_url(
                    'get_object',
                    Params={
                        'Bucket': loc['Bucket'],
                        'Key': loc['Key'],
                        'ResponseContentDisposition': f"attachment; filename={item['filename']}"
                    },
                    ExpiresIn=3600
                )
                item['link'] = presigned_url
                item['database'] = 's3'

        return fix_cors({'statusCode': 200, 'body': json.dumps(items)})
    except Exception as e:
        return fix_cors({'statusCode': 500, 'body': json.dumps({'error': str(e)})})

