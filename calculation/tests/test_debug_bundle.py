import sys
import unittest
from pathlib import Path
from unittest.mock import patch

DEBUG_BUNDLE_DIR = Path(__file__).resolve().parents[1] / "debug_bundle"
sys.path.insert(0, str(DEBUG_BUNDLE_DIR))

import debug_bundle


class FakeS3Client:
    def __init__(self):
        self.uploads = []

    def upload_file(self, filename, bucket, key):
        self.uploads.append((filename, bucket, key))

    def generate_presigned_url(self, *_args, **_kwargs):
        return "https://example.invalid/debug"


class DebugBundleTests(unittest.TestCase):
    def test_status_marker_is_uploaded_before_large_debug_bundle(self):
        fake_s3 = FakeS3Client()
        event = {
            "pipeline": "pipeline-1",
            "alias": "large job",
            "user_id": "user-1",
            "task": {"name": "ac", "options": {"reconstructor": {"name": "sense"}}},
            "fargateError": {"Cause": "task timed out"},
        }

        with (
            patch.object(debug_bundle, "s3_client", fake_s3),
            patch.object(debug_bundle, "FAILED_BUCKET", "failed-bucket"),
            patch.object(debug_bundle, "SNS_TOPIC_ARN", ""),
        ):
            result = debug_bundle.build_debug_bundle(event)

        self.assertTrue(result["success"])
        self.assertEqual(len(fake_s3.uploads), 2)
        self.assertTrue(fake_s3.uploads[0][2].startswith("MR Optimum/user-1/"))
        self.assertEqual(fake_s3.uploads[1][2], "debug-bundles/pipeline-1.zip")


if __name__ == "__main__":
    unittest.main()
