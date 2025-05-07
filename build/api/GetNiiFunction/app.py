import json
import os
import boto3
import zipfile

os.environ['CURL_CA_BUNDLE'] = ''

def lambda_handler(event, context):
    try:
        location = json.loads(event.get("body", "{}"))
        file_key = location["Key"]
        bucket_name = location["Bucket"]

        local_path = "/tmp/mri.zip"
        s3 = boto3.resource("s3")
        s3.Bucket(bucket_name).download_file(file_key, local_path)

        with zipfile.ZipFile(local_path, 'r') as archive:
            info_list = archive.infolist()
            filenames = [f.filename for f in info_list]

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "ZIP file processed successfully",
                "filenames": filenames
            }),
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
