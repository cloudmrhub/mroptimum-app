import json
import os
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


TEMPLATE = Path(__file__).resolve().parents[1] / "deploy" / "template.yaml"


def load_dispatcher_source():
    lines = TEMPLATE.read_text().splitlines()
    start = next(i for i, line in enumerate(lines) if line.strip() == "InlineCode: |") + 1
    source_lines = []
    for line in lines[start:]:
        if line and not line.startswith("        "):
            break
        source_lines.append(line[8:] if line else "")
    return "\n".join(source_lines)


class FakeEcsClient:
    def __init__(self):
        self.run_calls = []

    def run_task(self, **kwargs):
        self.run_calls.append(kwargs)
        return {"tasks": [{"taskArn": "arn:aws:ecs:task/test"}], "failures": []}


class FakeS3Client:
    def __init__(self):
        self.put_calls = []

    def put_object(self, **kwargs):
        self.put_calls.append(kwargs)


class DispatcherTests(unittest.TestCase):
    def test_api_key_authentication_is_case_insensitive(self):
        ecs = FakeEcsClient()
        s3 = FakeS3Client()
        fake_boto3 = types.ModuleType("boto3")
        fake_boto3.client = lambda name: ecs if name == "ecs" else s3
        environment = {
            "CLUSTER_NAME": "test-cluster",
            "TASK_DEFINITION": "test-task",
            "JOB_PAYLOAD_BUCKET": "job-payload-bucket",
            "SUBNETS": '["subnet-1","subnet-2"]',
            "SECURITY_GROUP": "sg-1",
            "WORKER_API_KEY": "correct-key",
        }

        namespace = {}
        with patch.dict(sys.modules, {"boto3": fake_boto3}), patch.dict(
            os.environ, environment, clear=True
        ):
            exec(load_dispatcher_source(), namespace)
            response = namespace["handler"](
                {
                    "httpMethod": "POST",
                    "headers": {"X-Api-Key": "correct-key"},
                    "body": "{invalid-json",
                },
                None,
            )

        # Authentication passed; parsing deliberately invalid JSON is the next
        # check. The old implementation returned 401 for this header casing.
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(ecs.run_calls, [])
        self.assertEqual(s3.put_calls, [])

    def test_large_job_is_staged_and_ecs_override_stays_small(self):
        ecs = FakeEcsClient()
        s3 = FakeS3Client()

        fake_boto3 = types.ModuleType("boto3")
        fake_boto3.client = lambda name: ecs if name == "ecs" else s3
        environment = {
            "CLUSTER_NAME": "test-cluster",
            "TASK_DEFINITION": "test-task",
            "JOB_PAYLOAD_BUCKET": "job-payload-bucket",
            "SUBNETS": '["subnet-1","subnet-2"]',
            "SECURITY_GROUP": "sg-1",
            "WORKER_API_KEY": "",
        }

        namespace = {}
        with patch.dict(sys.modules, {"boto3": fake_boto3}), patch.dict(
            os.environ, environment, clear=True
        ):
            exec(load_dispatcher_source(), namespace)
            body = {
                "pipeline": "pipeline-1",
                "task": {"presigned_urls": ["x" * 2000 for _ in range(5)]},
            }
            response = namespace["handler"](
                {"httpMethod": "POST", "headers": {}, "body": json.dumps(body)},
                None,
            )

        self.assertEqual(response["statusCode"], 202)
        self.assertEqual(len(s3.put_calls), 1)
        self.assertEqual(json.loads(s3.put_calls[0]["Body"]), body)
        overrides = ecs.run_calls[0]["overrides"]
        self.assertLess(len(json.dumps(overrides)), 8192)
        environment_override = overrides["containerOverrides"][0]["environment"]
        self.assertEqual(
            {item["name"] for item in environment_override}, {"JOB_BUCKET", "JOB_KEY"}
        )


if __name__ == "__main__":
    unittest.main()
