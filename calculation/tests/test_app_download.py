import sys
import tempfile
import unittest
import json
import os
from io import BytesIO
from pathlib import Path
from unittest.mock import Mock, patch


SRC_DIR = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC_DIR))

import app  # noqa: E402


class DownloadFromS3Tests(unittest.TestCase):
    def test_presigned_download_preserves_compound_nifti_extension(self):
        response = Mock(status_code=200)
        response.iter_content.return_value = [b"nifti-data"]
        file_info = {
            "type": "s3",
            "filename": "fa_12ch_coil.nii.gz",
            "bucket": "example-bucket",
            "key": "maps/fa_12ch_coil.nii.gz",
            "presigned_url": "https://example.invalid/fa-map",
        }

        app.logger = Mock()
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch.object(app.requests, "get", return_value=response):
                app.download_from_s3(file_info, pt=temp_dir)

            downloaded = Path(file_info["filename"])
            self.assertEqual(downloaded.parent, Path(temp_dir))
            self.assertTrue(downloaded.name.endswith("_fa_12ch_coil.nii.gz"))
            self.assertEqual(downloaded.read_bytes(), b"nifti-data")
            self.assertEqual(file_info["type"], "local")


class LoadJobFromEnvironmentTests(unittest.TestCase):
    def test_loads_job_from_s3_reference(self):
        payload = {"pipeline": "pipeline-1", "task": {"name": "ac"}}
        s3_client = Mock()
        s3_client.get_object.return_value = {
            "Body": BytesIO(json.dumps(payload).encode("utf-8"))
        }

        with patch.dict(
            os.environ,
            {"JOB_BUCKET": "job-bucket", "JOB_KEY": "jobs/pipeline-1.json"},
            clear=True,
        ):
            loaded = app.load_job_from_environment(s3_client=s3_client)

        self.assertEqual(loaded, payload)
        s3_client.get_object.assert_called_once_with(
            Bucket="job-bucket", Key="jobs/pipeline-1.json"
        )

    def test_legacy_file_event_remains_supported(self):
        payload = {"pipeline": "legacy-pipeline"}
        with patch.dict(os.environ, {"FILE_EVENT": json.dumps(payload)}, clear=True):
            self.assertEqual(app.load_job_from_environment(), payload)

    def test_rejects_partial_s3_reference(self):
        with patch.dict(os.environ, {"JOB_BUCKET": "job-bucket"}, clear=True):
            with self.assertRaisesRegex(RuntimeError, "must be provided together"):
                app.load_job_from_environment()


if __name__ == "__main__":
    unittest.main()
