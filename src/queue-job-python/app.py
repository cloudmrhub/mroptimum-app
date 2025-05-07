import json
import os
import boto3
import uuid
import urllib3

def lambda_handler(event, context):
    try:
        # Step 1: Parse the request
        body = json.loads(event["body"])
        alias = body["alias"]
        task = body["task"]
        output = body.get("output", {})
        token = event["headers"].get("Authorization", "")

        # Step 2: Call the PipelineScheduler to get pipeline ID
        scheduler_url = os.environ["PipelineScheduler"]
        http = urllib3.PoolManager()
        scheduler_resp = http.request(
            "POST",
            scheduler_url,
            body=json.dumps({"alias": alias}),
            headers={"Content-Type": "application/json", "Authorization": token}
        )

        if scheduler_resp.status != 200:
            return {"statusCode": 502, "body": "PipelineScheduler failed."}

        pipeline_id = json.loads(scheduler_resp.data.decode("utf-8")).get("id")

        # Step 3: Build the job object
        job = {
            "pipeline": pipeline_id,
            "token": token,
            "output": output,
            "task": task
        }

        # Step 4: Write job to /tmp and create fake FILE_EVENT
        filename = f"{uuid.uuid4()}.json"
        filepath = f"/tmp/{filename}"
        with open(filepath, "w") as f:
            json.dump(job, f)

        file_event = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": os.environ["ResultsBucketName"]},
                        "object": {"key": filename}
                    }
                }
            ]
        }

        # Step 5: Upload job file to S3
        s3 = boto3.client("s3")
        s3.upload_file(filepath, os.environ["ResultsBucketName"], filename)

        # Step 6: Start Step Function
        sfn = boto3.client("stepfunctions")
        response = sfn.start_execution(
            stateMachineArn=os.environ["StateMachineArn"],
            input=json.dumps({
                "executionType": "fargate",
                "FILE_EVENT": json.dumps(file_event)
            })
        )

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Job queued successfully",
                "executionArn": response["executionArn"],
                "file": filename
            })
        }

    except Exception as e:
        return {"statusCode": 500, "body": str(e)}