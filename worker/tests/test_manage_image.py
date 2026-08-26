import hashlib
import sys
import unittest
from pathlib import Path

WORKER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(WORKER_DIR))

import manage


class FakeResponse:
    def __init__(self, *, json_data=None, content=b"", headers=None):
        self._json_data = json_data
        self.content = content
        self.headers = headers or {}

    def raise_for_status(self):
        return None

    def json(self):
        return self._json_data


class ImageResolutionTests(unittest.TestCase):
    def test_public_tag_is_resolved_to_manifest_digest(self):
        manifest = b'{"schemaVersion":2}'
        responses = iter(
            [
                FakeResponse(json_data={"token": "public-token"}),
                FakeResponse(content=manifest),
            ]
        )

        resolved = manage.resolve_public_image_digest(
            "public.ecr.aws/r2m7t0q6/cloudmrhub/mroptimum-fargate:latest",
            http_get=lambda *_args, **_kwargs: next(responses),
        )

        expected_digest = hashlib.sha256(manifest).hexdigest()
        self.assertEqual(
            resolved,
            "public.ecr.aws/r2m7t0q6/cloudmrhub/mroptimum-fargate"
            f"@sha256:{expected_digest}",
        )

    def test_existing_digest_is_unchanged(self):
        image = "public.ecr.aws/example/repo@sha256:abc123"
        self.assertEqual(manage.resolve_public_image_digest(image), image)


if __name__ == "__main__":
    unittest.main()
