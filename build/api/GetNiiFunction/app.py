import json
import boto3
import os
import zipfile

os.environ['CURL_CA_BUNDLE'] = ''

s3 = boto3.resource("s3")
s3_client = boto3.client("s3")


def lambda_handler(event, context):
    try:
        location = json.loads(event["body"])
        file_key = location.get("key") or location.get("Key")
        bucket_name = location.get("bucket") or location.get("Bucket")

        if not file_key or not bucket_name:
            return _response(400, "Missing 'key' or 'bucket' in request body.")

        # Download zip from S3
        local_zip_path = "/tmp/archive.zip"
        s3.Bucket(bucket_name).download_file(file_key, local_zip_path)

        with zipfile.ZipFile(local_zip_path, 'r') as archive:
            if 'info.json' not in archive.namelist():
                return _response(400, "'info.json' not found in zip archive.")

            info = json.loads(archive.read('info.json'))
            data_entries = info.get('data', [])

            for entry in data_entries:
                inner_filename = entry.get('filename')
                if not inner_filename:
                    continue

                extracted_file = archive.read(inner_filename)
                target_key = f"unzipped/{file_key}_{inner_filename}"
                s3_client.put_object(Bucket=bucket_name, Key=target_key, Body=extracted_file)

                # Generate pre-signed URL
                url = s3_client.generate_presigned_url(
                    'get_object',
                    Params={'Bucket': bucket_name, 'Key': target_key},
                    ExpiresIn=3600
                )
                entry['link'] = url

        return _response(200, info)

    except Exception as e:
        return _response(500, f"Error: {str(e)}")


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            'Access-Control-Allow-Origin': '*'
        },
        "body": json.dumps(body)
    }
