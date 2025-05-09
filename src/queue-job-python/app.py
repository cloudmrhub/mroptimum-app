import json
import os
import boto3
import uuid
import datetime

s3 = boto3.client("s3")

def lambda_handler(event, context):
    print("Received event:", json.dumps(event))

    body = json.loads(event["body"])
    alias = body.get("alias", "alias")

    job_id = str(uuid.uuid4())
    now = datetime.datetime.now()
    now_str = now.strftime("%Y-%m-%d-%H-%M-%S")
    key = f"{alias}/{now_str}/{job_id}.json"

    print(f"Creating job file at: {key}")

    bucket = os.environ["ResultsBucketName"]
    failed_bucket = os.environ["FailedBucketName"]

    try:
        # Step 1: Write input JSON to S3
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(body),
            ContentType="application/json"
        )

        print(f"Uploaded input JSON to s3://{bucket}/{key}")

        # Step 2: Prepare the FILE_EVENT object
        file_event = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": bucket},
                        "object": {"key": key}
                    }
                }
            ]
        }

        # Step 3: Determine executionType dynamically from payload
        execution_type = body.get("executionType", "fargate")  # Default is fargate
        print(f"Triggering Step Function with executionType: {execution_type}")

        # Step 4: Start Step Function Execution
        sfn = boto3.client("stepfunctions")
        response = sfn.start_execution(
            stateMachineArn=os.environ["StateMachineArn"],
            input=json.dumps({
                "executionType": execution_type,
                "FILE_EVENT": json.dumps(file_event)
            })
        )

        print("Step Function started:", response["executionArn"])

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Job submitted successfully",
                "jobId": job_id,
                "executionType": execution_type,
                "executionArn": response["executionArn"]
            })
        }

    except Exception as e:
        print("Error submitting job:", str(e))

        # Upload the job input to the failed bucket
        s3.put_object(
            Bucket=failed_bucket,
            Key=key,
            Body=json.dumps(body),
            ContentType="application/json"
        )

        return {
            "statusCode": 500,
            "body": json.dumps({"message": "PipelineScheduler failed."})
        }
