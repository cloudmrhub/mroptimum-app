import sys
import tempfile
import unittest
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


if __name__ == "__main__":
    unittest.main()
