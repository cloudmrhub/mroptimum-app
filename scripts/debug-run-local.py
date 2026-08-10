#!/usr/bin/env python3
"""
Download S3 files for a failed task and run it locally for debugging.

Usage:
    # Run a specific task by pipeline ID or task ID:
    python scripts/debug-run-local.py --task-id e924b60b-5d68-4e44-bd98-2893456e9b1c

    # Or from the debug-failed-tasks.json (pick by index):
    python scripts/debug-run-local.py --index 0

    # Just download files without running:
    python scripts/debug-run-local.py --task-id <id> --download-only

    # Use a specific AWS profile:
    python scripts/debug-run-local.py --task-id <id> --profile nyu

Prerequisites:
    - AWS credentials configured (for S3 downloads)
    - mrotools installed (pip install mrotools)
    - Run debug-query-pipelines.py first to generate debug-failed-tasks.json
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import boto3

SCRIPT_DIR = Path(__file__).parent
FAILED_TASKS_FILE = SCRIPT_DIR / "debug-failed-tasks.json"
DEBUG_DIR = Path("/tmp/mroptimum-debug")


def load_failed_tasks():
    """Load the failed tasks JSON."""
    if not FAILED_TASKS_FILE.exists():
        print(f"[ERROR] {FAILED_TASKS_FILE} not found.")
        print("  Run: python scripts/debug-query-pipelines.py")
        sys.exit(1)
    with open(FAILED_TASKS_FILE) as f:
        return json.load(f)


def find_task(data, task_id=None, pipeline_id=None, index=None):
    """Find a task entry by task_id, pipeline_id, or index."""
    all_tasks = data.get("all_tasks", [])
    failed_tasks = data.get("failed_tasks", [])

    if index is not None:
        tasks = failed_tasks if failed_tasks else all_tasks
        if 0 <= index < len(tasks):
            return tasks[index]
        print(f"[ERROR] Index {index} out of range (0..{len(tasks)-1})")
        sys.exit(1)

    # Search by task_id or pipeline_id
    search_id = task_id or pipeline_id
    for t in all_tasks:
        if (t.get("task_id") == search_id or
            t.get("pipeline_id") == search_id or
            t.get("raw", {}).get("_id") == search_id or
            t.get("raw", {}).get("id") == search_id):
            return t

    print(f"[ERROR] Task not found: {search_id}")
    print(f"  Available IDs (first 10):")
    for t in all_tasks[:10]:
        print(f"    pipeline={t['pipeline_id']}  task={t.get('task_id', 'N/A')}  status={t['status']}  alias={t['alias'][:30]}")
    sys.exit(1)


def download_s3_file(bucket, key, local_path, profile=None):
    """Download a file from S3."""
    session = boto3.Session(profile_name=profile) if profile else boto3.Session()
    s3 = session.resource("s3")
    local_path = Path(local_path)
    local_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"  Downloading s3://{bucket}/{key} → {local_path}")
    s3.Bucket(bucket).download_file(key, str(local_path))
    return local_path


def extract_s3_files(task_entry):
    """Extract S3 file references from task JSON."""
    files = []
    task = task_entry.get("task") or task_entry.get("raw", {}).get("task") or {}
    recon_opts = (task.get("options", {})
                  .get("reconstructor", {})
                  .get("options", {}))

    # Signal file
    if "signal" in recon_opts:
        sig_opts = recon_opts["signal"].get("options", {})
        if sig_opts.get("bucket") and sig_opts.get("key"):
            files.append({
                "role": "signal",
                "bucket": sig_opts["bucket"],
                "key": sig_opts["key"],
                "filename": sig_opts.get("filename", sig_opts["key"]),
            })

    # Noise file
    if "noise" in recon_opts:
        noise_opts = recon_opts["noise"].get("options", {})
        if noise_opts.get("bucket") and noise_opts.get("key"):
            files.append({
                "role": "noise",
                "bucket": noise_opts["bucket"],
                "key": noise_opts["key"],
                "filename": noise_opts.get("filename", noise_opts["key"]),
            })

    return files


def prepare_local_task(task_entry, work_dir, profile=None):
    """Download S3 files and rewrite task JSON for local execution."""
    work_dir = Path(work_dir)
    work_dir.mkdir(parents=True, exist_ok=True)
    data_dir = work_dir / "data"
    data_dir.mkdir(exist_ok=True)

    # Get the task payload
    task = task_entry.get("task") or task_entry.get("raw", {}).get("task")
    if not task:
        print("[ERROR] No 'task' field found in entry")
        print(f"  Available keys: {list(task_entry.keys())}")
        print(f"  Raw keys: {list(task_entry.get('raw', {}).keys())}")
        sys.exit(1)

    # Deep copy to modify
    task = json.loads(json.dumps(task))

    # Download S3 files and rewrite paths to local
    s3_files = extract_s3_files(task_entry)
    for finfo in s3_files:
        local_path = data_dir / finfo["filename"]
        if local_path.exists():
            print(f"  [CACHED] {finfo['role']}: {local_path}")
        else:
            download_s3_file(finfo["bucket"], finfo["key"], local_path, profile=profile)

        # Rewrite the task JSON to point to local file
        recon_opts = task["options"]["reconstructor"]["options"]
        if finfo["role"] == "signal" and "signal" in recon_opts:
            recon_opts["signal"]["options"]["type"] = "local"
            recon_opts["signal"]["options"]["filename"] = str(local_path)
        elif finfo["role"] == "noise" and "noise" in recon_opts:
            recon_opts["noise"]["options"]["type"] = "local"
            recon_opts["noise"]["options"]["filename"] = str(local_path)

    # Write local task JSON
    task_json_path = work_dir / "task.json"
    with open(task_json_path, "w") as f:
        json.dump(task, f, indent=2)
    print(f"\n[OK] Task JSON written: {task_json_path}")

    return task_json_path, task


def run_locally(task_json_path, work_dir):
    """Run mrotools.snr locally with the task JSON."""
    out_dir = Path(work_dir) / "output"
    out_dir.mkdir(exist_ok=True)
    log_path = Path(work_dir) / "run.log"

    cmd = [
        sys.executable, "-m", "mrotools.snr",
        "-j", str(task_json_path),
        "-o", str(out_dir),
        "--no-parallel",
        "--no-matlab",
        "--no-coilsens",
        "--no-gfactor",
        "--no-verbose",
        "-l", str(log_path),
    ]

    print(f"\n[INFO] Running: {' '.join(cmd)}")
    print(f"       Output:  {out_dir}")
    print(f"       Log:     {log_path}")
    print(f"{'='*60}\n")

    result = subprocess.run(cmd, capture_output=False)

    print(f"\n{'='*60}")
    if result.returncode == 0:
        print(f"[OK] Computation completed successfully!")
        # Show output files
        if out_dir.exists():
            print(f"\nOutput files:")
            for f in sorted(out_dir.rglob("*")):
                if f.is_file():
                    size = f.stat().st_size
                    print(f"  {f.relative_to(out_dir)}: {size:,} bytes")
    else:
        print(f"[FAILED] Exit code: {result.returncode}")
        if log_path.exists():
            print(f"\nLog tail:")
            with open(log_path) as f:
                log_data = json.load(f)
            # Show last few entries
            for entry in log_data[-5:]:
                print(f"  [{entry.get('type', '?')}] {entry.get('what', '')}")

    return result.returncode


def main():
    parser = argparse.ArgumentParser(description="Debug failed MR Optimum tasks locally")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--task-id", "-t", help="Task ID or Pipeline ID to debug")
    group.add_argument("--index", "-i", type=int, help="Index in failed tasks list (0-based)")

    parser.add_argument("--profile", "-p", default="nyu", help="AWS profile for S3 access (default: nyu)")
    parser.add_argument("--download-only", "-d", action="store_true", help="Only download files, don't run")
    parser.add_argument("--work-dir", "-w", help="Working directory (default: /tmp/mroptimum-debug/<id>)")

    args = parser.parse_args()

    # Load tasks
    data = load_failed_tasks()

    # Find the task
    task_entry = find_task(data, task_id=args.task_id, index=args.index)
    task_id = args.task_id or task_entry.get("pipeline_id", f"idx-{args.index}")

    print(f"\n{'='*60}")
    print(f"  Debugging Task")
    print(f"{'='*60}")
    print(f"  Pipeline ID: {task_entry.get('pipeline_id')}")
    print(f"  Task ID:     {task_entry.get('task_id', 'N/A')}")
    print(f"  Status:      {task_entry.get('status')}")
    print(f"  Alias:       {task_entry.get('alias')}")
    print(f"  Created:     {task_entry.get('created_at')}")
    print()

    # Setup work directory
    work_dir = Path(args.work_dir) if args.work_dir else DEBUG_DIR / task_id
    work_dir.mkdir(parents=True, exist_ok=True)
    print(f"  Work dir:    {work_dir}")
    print()

    # Download and prepare
    print("[INFO] Downloading S3 files...")
    task_json_path, task = prepare_local_task(task_entry, work_dir, profile=args.profile)

    # Show task summary
    task_name = task.get("name", "?")
    recon_name = task.get("options", {}).get("reconstructor", {}).get("name", "?")
    print(f"\n  Calculation: {task_name} / {recon_name}")

    if args.download_only:
        print(f"\n[OK] Files downloaded. Run manually with:")
        print(f"  python -m mrotools.snr -j {task_json_path} -o {work_dir}/output --no-parallel --no-verbose -l {work_dir}/run.log")
        return

    # Run locally
    exit_code = run_locally(task_json_path, work_dir)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
