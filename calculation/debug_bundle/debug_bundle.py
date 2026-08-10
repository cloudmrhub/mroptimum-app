"""
Debug Bundle Lambda — invoked by Step Functions when a task completely fails.

Receives the full task event (same payload Lambda/Fargate received),
downloads all referenced data files, bundles everything into one
self-contained zip, uploads to debug-bundles/ in the failed bucket,
and sends a presigned download link via SNS.

The zip contains:
- event.json          — original event (for reference)
- task_local.json     — rewritten with type=local so mrotools runs out of the box
- data/               — signal, noise, and any other referenced files
- error_info.json     — the error that caused the failure (from $.computeError)
- REPRODUCE.md        — instructions for developers
"""

import json
import os
import shutil
import tempfile
import traceback
import uuid
import zipfile
from pathlib import Path

import boto3

SNS_TOPIC_ARN = os.environ.get("DEBUG_SNS_TOPIC_ARN", "")
FAILED_BUCKET = os.environ.get("FAILED_BUCKET", "")
PRESIGNED_URL_EXPIRY = 7 * 24 * 3600  # 7 days

s3_client = boto3.client("s3")
sns_client = boto3.client("sns")


def handler(event, context):
    """
    Step Functions invokes this with the full state machine input.
    The event contains the original task payload plus $.computeError
    added by the Catch clause.
    """
    try:
        return build_debug_bundle(event)
    except Exception as e:
        print(f"DebugBundle error: {e}")
        traceback.print_exc()
        # Don't fail the state machine further — just log
        return {"success": False, "error": str(e)}


def build_debug_bundle(event):
    work_dir = Path(tempfile.mkdtemp())

    try:
        # Extract task info from the event
        task = event.get("task", {})
        pipeline_id = event.get("pipeline") or task.get("pipelineid") or str(uuid.uuid4())[:8]
        alias = event.get("alias", "unknown")
        user_id = event.get("user_id", "unknown")
        task_name = task.get("name", "?")
        recon_name = task.get("options", {}).get("reconstructor", {}).get("name", "?")
        compute_error = event.get("computeError", {})

        print(f"Building debug bundle: pipeline={pipeline_id} alias={alias} task={task_name}/{recon_name}")

        # Prepare bundle directory
        bundle_dir = work_dir / "bundle"
        bundle_dir.mkdir()
        data_dir = bundle_dir / "data"
        data_dir.mkdir()

        # 1) Write original event.json
        with open(bundle_dir / "event.json", "w") as f:
            json.dump(event, f, indent=2, default=str)

        # 2) Write error info
        with open(bundle_dir / "error_info.json", "w") as f:
            json.dump(compute_error, f, indent=2, default=str)

        # 3) Download data files listed in task["files"]
        files_list = task.get("files", [])
        recon_opts = task.get("options", {}).get("reconstructor", {}).get("options", {})
        downloaded = []

        for file_role in files_list:
            if file_role not in recon_opts:
                continue
            file_opts = recon_opts[file_role].get("options", {})
            file_bucket = file_opts.get("bucket")
            file_s3_key = file_opts.get("key")

            if not file_bucket or not file_s3_key:
                continue

            # Local filename: role_originalname
            original_name = Path(file_s3_key).name
            local_name = f"{file_role}_{original_name}"
            local_path = data_dir / local_name

            try:
                print(f"  Downloading {file_role}: s3://{file_bucket}/{file_s3_key}")
                s3_client.download_file(file_bucket, file_s3_key, str(local_path))
                downloaded.append({
                    "role": file_role,
                    "bucket": file_bucket,
                    "key": file_s3_key,
                    "local": f"data/{local_name}",
                })
            except Exception as e:
                print(f"  FAILED: {e}")
                downloaded.append({
                    "role": file_role,
                    "bucket": file_bucket,
                    "key": file_s3_key,
                    "error": str(e),
                })

        # 4) Build task_local.json — getCMRFile-compatible local format
        local_task = json.loads(json.dumps(task))
        local_recon_opts = local_task.get("options", {}).get("reconstructor", {}).get("options", {})

        for dl in downloaded:
            if "error" in dl:
                continue
            role = dl["role"]
            if role in local_recon_opts:
                opts = local_recon_opts[role]["options"]
                opts["type"] = "local"
                opts["filename"] = dl["local"]

        with open(bundle_dir / "task_local.json", "w") as f:
            json.dump(local_task, f, indent=2)

        # 5) Write REPRODUCE.md
        error_cause = compute_error.get("Cause", compute_error.get("cause", "unknown"))
        error_name = compute_error.get("Error", compute_error.get("error", ""))

        md = f"""# Debug Bundle — Failed Task

| Field | Value |
|-------|-------|
| Pipeline | `{pipeline_id}` |
| Alias | {alias} |
| User | `{user_id}` |
| Task | {task_name} / {recon_name} |
| Error | {error_name} |

## Error Detail
```
{str(error_cause)[:2000]}
```

## Data Files
"""
        for dl in downloaded:
            if "error" in dl:
                md += f"- **{dl['role']}**: DOWNLOAD FAILED — {dl['error']}\n"
            else:
                md += f"- **{dl['role']}**: `{dl['local']}`\n"

        md += f"""
## Reproduce Locally

```bash
unzip debug_bundle.zip -d debug_task
cd debug_task

python -m mrotools.snr \\
  -j task_local.json \\
  -o output \\
  --no-parallel \\
  --no-verbose \\
  -l run.log
```

## Original S3 Locations
"""
        for dl in downloaded:
            md += f"- **{dl['role']}**: `s3://{dl['bucket']}/{dl['key']}`\n"

        (bundle_dir / "REPRODUCE.md").write_text(md)

        # 6) Zip the bundle
        bundle_zip_path = work_dir / "debug_bundle.zip"
        with zipfile.ZipFile(bundle_zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for file_path in sorted(bundle_dir.rglob("*")):
                if file_path.is_file():
                    arcname = str(file_path.relative_to(bundle_dir))
                    zf.write(file_path, arcname)

        bundle_size_mb = bundle_zip_path.stat().st_size / (1024 * 1024)
        print(f"  Bundle: {bundle_size_mb:.1f} MB")

        # 7) Upload to debug-bundles/ in the failed bucket
        bucket = FAILED_BUCKET
        debug_key = f"debug-bundles/{pipeline_id}.zip"
        s3_client.upload_file(str(bundle_zip_path), bucket, debug_key)
        print(f"  Uploaded: s3://{bucket}/{debug_key}")

        # 8) Generate presigned URL (7 days)
        presigned_url = s3_client.generate_presigned_url(
            "get_object",
            Params={"Bucket": bucket, "Key": debug_key},
            ExpiresIn=PRESIGNED_URL_EXPIRY,
        )

        # 9) Publish to SNS
        if SNS_TOPIC_ARN:
            subject = f"FAILED: {alias} ({task_name}/{recon_name})"
            if len(subject) > 100:
                subject = subject[:97] + "..."

            message = (
                f"MR Optimum task failed.\n\n"
                f"Pipeline: {pipeline_id}\n"
                f"Alias: {alias}\n"
                f"User: {user_id}\n"
                f"Task: {task_name} / {recon_name}\n"
                f"Bundle: {bundle_size_mb:.1f} MB\n\n"
                f"Error: {error_name}\n"
                f"{str(error_cause)[:500]}\n\n"
                f"Download debug bundle (7 days):\n{presigned_url}\n\n"
                f"Reproduce:\n"
                f"  wget -O debug.zip '<url above>'\n"
                f"  unzip debug.zip -d debug_task && cd debug_task\n"
                f"  python -m mrotools.snr -j task_local.json -o output "
                f"--no-parallel --no-verbose -l run.log\n"
            )

            sns_client.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=message)
            print("  SNS sent")

        return {
            "success": True,
            "bundle": f"s3://{bucket}/{debug_key}",
            "size_mb": round(bundle_size_mb, 1),
        }

    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
