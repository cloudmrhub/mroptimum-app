#!/usr/bin/env python3
"""
Query all MR Optimum pipelines from CloudMR Brain API and export failed task info.

Usage:
    source exports_user.sh
    python scripts/debug-query-pipelines.py

Or with inline credentials:
    CLOUDMR_EMAIL="user@email.com" CLOUDMR_PASSWORD="pass" python scripts/debug-query-pipelines.py

Output:
    scripts/debug-failed-tasks.json — JSON array of failed tasks with all info needed
                                      to reproduce them locally.
"""

import json
import os
import sys
import requests
from pathlib import Path

# Configuration
API_URL = os.getenv("CLOUDMR_API_URL", "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod")
EMAIL = os.getenv("CLOUDMR_EMAIL", os.getenv("EMAIL", ""))
PASSWORD = os.getenv("CLOUDMR_PASSWORD", os.getenv("PASSWORD", ""))
CLOUDAPP_NAME = "MR Optimum"
OUTPUT_FILE = Path(__file__).parent / "debug-failed-tasks.json"


def login(api_url, email, password):
    """Login to CloudMR Brain and return tokens."""
    print(f"[INFO] Logging in as {email}...")
    resp = requests.post(f"{api_url}/api/auth/login", json={"email": email, "password": password})
    resp.raise_for_status()
    data = resp.json()
    if not data.get("success"):
        print(f"[ERROR] Login failed: {data.get('message', 'Unknown error')}")
        sys.exit(1)
    print(f"[OK] Logged in (user_id: {data.get('user_id')})")
    return data


def get_cloudapp_id(api_url, token, app_name):
    """Find the CloudApp ID for MR Optimum."""
    resp = requests.get(f"{api_url}/api/cloudapp/list", headers={"Authorization": f"Bearer {token}"})
    resp.raise_for_status()
    data = resp.json()
    apps = data.get("apps", data if isinstance(data, list) else [])
    for app in apps:
        if app.get("name") == app_name:
            return app.get("appId") or app.get("id")
    print(f"[ERROR] CloudApp '{app_name}' not found")
    print(f"  Available: {[a.get('name') for a in apps]}")
    sys.exit(1)


def list_pipelines(api_url, token, cloudapp_id=None):
    """List all pipelines, optionally filtered by cloudapp."""
    if cloudapp_id:
        url = f"{api_url}/api/pipeline/list/{cloudapp_id}"
    else:
        url = f"{api_url}/api/pipeline/list"
    resp = requests.get(url, headers={"Authorization": f"Bearer {token}"})
    resp.raise_for_status()
    data = resp.json()
    # API may return {pipelines: [...]} or just [...]
    if isinstance(data, list):
        return data
    return data.get("pipelines", data.get("data", []))


def get_pipeline_details(api_url, token, pipeline_id):
    """Get detailed info for a specific pipeline."""
    resp = requests.get(
        f"{api_url}/api/pipeline/{pipeline_id}",
        headers={"Authorization": f"Bearer {token}"}
    )
    if resp.status_code == 404:
        return None
    resp.raise_for_status()
    return resp.json()


def main():
    if not EMAIL or not PASSWORD:
        print("[ERROR] CLOUDMR_EMAIL and CLOUDMR_PASSWORD must be set")
        print("  Run: source exports_user.sh")
        sys.exit(1)

    # 1. Login
    auth = login(API_URL, EMAIL, PASSWORD)
    token = auth.get("id_token") or auth.get("token")
    user_id = auth.get("user_id")

    # 2. Find MR Optimum app
    print(f"[INFO] Looking up CloudApp '{CLOUDAPP_NAME}'...")
    cloudapp_id = get_cloudapp_id(API_URL, token, CLOUDAPP_NAME)
    print(f"[OK] CloudApp ID: {cloudapp_id}")

    # 3. List all pipelines
    print(f"[INFO] Fetching pipelines...")
    pipelines = list_pipelines(API_URL, token, cloudapp_id)
    print(f"[OK] Found {len(pipelines)} pipelines")

    # 4. Collect info on each pipeline
    failed_tasks = []
    all_tasks = []

    for i, p in enumerate(pipelines):
        pid = p.get("pipeline") or p.get("pipelineId") or p.get("id") or p.get("_id")
        status = p.get("status", "unknown")
        alias = p.get("alias", "")
        task_id = p.get("taskId") or p.get("task_id") or ""
        user = p.get("user_id") or p.get("userId") or user_id

        entry = {
            "pipeline_id": pid,
            "task_id": task_id,
            "status": status,
            "alias": alias,
            "user_id": user,
            "created_at": p.get("created_at") or p.get("createdAt") or p.get("timestamp") or "",
            "task": p.get("task"),
            "output": p.get("output"),
            "raw": p,
        }

        all_tasks.append(entry)

        # Consider failed if status indicates failure
        status_lower = str(status).lower()
        if any(s in status_lower for s in ["fail", "error", "timeout", "abort"]):
            failed_tasks.append(entry)

    # 5. Sort by creation date (most recent first)
    all_tasks.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    failed_tasks.sort(key=lambda x: x.get("created_at", ""), reverse=True)

    # 6. Print summary
    print(f"\n{'='*60}")
    print(f"  Pipeline Summary")
    print(f"{'='*60}")
    print(f"  Total pipelines: {len(all_tasks)}")
    print(f"  Failed:          {len(failed_tasks)}")
    print()

    # Status breakdown
    statuses = {}
    for t in all_tasks:
        s = t["status"]
        statuses[s] = statuses.get(s, 0) + 1
    print("  Status breakdown:")
    for s, count in sorted(statuses.items(), key=lambda x: -x[1]):
        print(f"    {s}: {count}")

    # 7. Write output
    output = {
        "query_info": {
            "api_url": API_URL,
            "cloudapp_name": CLOUDAPP_NAME,
            "cloudapp_id": cloudapp_id,
            "user_id": user_id,
            "total_pipelines": len(all_tasks),
            "failed_pipelines": len(failed_tasks),
        },
        "failed_tasks": failed_tasks,
        "all_tasks": all_tasks,
    }

    with open(OUTPUT_FILE, "w") as f:
        json.dump(output, f, indent=2, default=str)

    print(f"\n[OK] Written to: {OUTPUT_FILE}")
    print(f"     Failed tasks: {len(failed_tasks)}")
    print(f"     All tasks: {len(all_tasks)}")

    # 8. Show first few failed tasks
    if failed_tasks:
        print(f"\n  Recent failed tasks:")
        for t in failed_tasks[:10]:
            print(f"    - [{t['status']}] {t['alias'][:40]:<40} pipeline={t['pipeline_id']}")


if __name__ == "__main__":
    main()
