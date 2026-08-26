import io
import json
import sys
import types
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch


TEMPLATE = Path(__file__).resolve().parents[1] / "deploy" / "template.yaml"


def load_reporter_source():
    lines = TEMPLATE.read_text().splitlines()
    resource_start = next(
        index
        for index, line in enumerate(lines)
        if line.strip() == "TaskFailureReporterFunction:"
    )
    start = next(
        index
        for index, line in enumerate(lines[resource_start:], resource_start)
        if line.strip() == "InlineCode: |"
    ) + 1
    source_lines = []
    for line in lines[start:]:
        if line and not line.startswith("        "):
            break
        source_lines.append(line[8:] if line else "")
    return "\n".join(source_lines)


class FakeEcsClient:
    def describe_tasks(self, **_kwargs):
        return {
            "tasks": [
                {
                    "overrides": {
                        "containerOverrides": [
                            {
                                "environment": [
                                    {"name": "JOB_BUCKET", "value": "jobs-bucket"},
                                    {"name": "JOB_KEY", "value": "jobs/pipeline-1.json"},
                                ]
                            }
                        ]
                    }
                }
            ]
        }


class FakeS3Client:
    def get_object(self, **_kwargs):
        job = {
            "pipeline": "pipeline-1",
            "alias": "test job",
            "user_id": "user-1",
            "presigned_failure_status_upload_url": "https://example.invalid/failure",
        }
        return {"Body": io.BytesIO(json.dumps(job).encode())}


class UploadResponse:
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return b""


class FailureReporterTests(unittest.TestCase):
    def test_stopped_task_uploads_small_standard_failure_marker(self):
        ecs = FakeEcsClient()
        s3 = FakeS3Client()
        fake_boto3 = types.ModuleType("boto3")
        fake_boto3.client = lambda name: ecs if name == "ecs" else s3
        namespace = {}

        with patch.dict(sys.modules, {"boto3": fake_boto3}):
            exec(load_reporter_source(), namespace)

        uploads = []

        def fake_urlopen(request, timeout):
            uploads.append((request, timeout))
            return UploadResponse()

        namespace["urllib"].request.urlopen = fake_urlopen
        result = namespace["handler"](
            {
                "detail": {
                    "clusterArn": "arn:aws:ecs:cluster/test",
                    "taskArn": "arn:aws:ecs:task/test",
                    "lastStatus": "STOPPED",
                    "stoppedReason": "CannotPullContainerError",
                    "containers": [{"name": "worker", "reason": "image not found"}],
                }
            },
            None,
        )

        self.assertTrue(result["reported"])
        self.assertEqual(len(uploads), 1)
        request, timeout = uploads[0]
        self.assertEqual(request.get_method(), "PUT")
        self.assertEqual(timeout, 60)
        with zipfile.ZipFile(io.BytesIO(request.data)) as archive:
            info = json.loads(archive.read("info.json"))
        self.assertEqual(info["headers"]["options"]["pipelineid"], "pipeline-1")
        self.assertIn("CannotPullContainerError", info["headers"]["log"][0]["what"])


if __name__ == "__main__":
    unittest.main()
