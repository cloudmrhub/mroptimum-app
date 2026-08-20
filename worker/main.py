"""
MR Optimum Worker Service — API-based Mode 2

A self-contained HTTP service that receives computation jobs from CloudMR Brain,
runs mrotools locally, and reports results back.

Can run anywhere: Docker, local machine, SLURM cluster, any cloud.

Endpoints:
    GET  /health           — Liveness check (Brain pings periodically)
    POST /compute          — Accept a job, run it, report results
    GET  /jobs             — List recent jobs (for debugging)
    GET  /jobs/{job_id}    — Get status of a specific job
"""

import asyncio
import json
import os
import sys
import traceback
import uuid
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Optional

import requests
from fastapi import BackgroundTasks, FastAPI, Header, HTTPException
from pydantic import BaseModel

# Add calculation/src to path so we can import app.py's do_process
CALC_SRC = Path(__file__).parent.parent / "calculation" / "src"
sys.path.insert(0, str(CALC_SRC))

from app import do_process

# =============================================================================
# Configuration (via environment variables)
# =============================================================================
WORKER_API_KEY = os.environ.get("WORKER_API_KEY", "")
BRAIN_API_URL = os.environ.get("BRAIN_API_URL", "https://brain.aws.cloudmrhub.com/Prod")
BRAIN_TOKEN = os.environ.get("BRAIN_TOKEN", "")  # For reporting results back
WORKER_ID = os.environ.get("WORKER_ID", str(uuid.uuid4())[:8])
MAX_CONCURRENT_JOBS = int(os.environ.get("MAX_CONCURRENT_JOBS", "2"))

# =============================================================================
# App
# =============================================================================
app = FastAPI(
    title="MR Optimum Worker",
    description="Self-hosted computation worker for MR Optimum (Mode 2)",
    version="1.0.0",
)


# =============================================================================
# Models
# =============================================================================
class JobStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class JobInfo(BaseModel):
    job_id: str
    pipeline_id: Optional[str] = None
    alias: Optional[str] = None
    status: JobStatus
    submitted_at: str
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    error: Optional[str] = None
    result: Optional[dict] = None


# In-memory job store (simple — for production use Redis or a DB)
jobs: dict[str, JobInfo] = {}
_semaphore: Optional[asyncio.Semaphore] = None


def get_semaphore():
    global _semaphore
    if _semaphore is None:
        _semaphore = asyncio.Semaphore(MAX_CONCURRENT_JOBS)
    return _semaphore


# =============================================================================
# Auth
# =============================================================================
def verify_api_key(x_api_key: Optional[str] = Header(None)):
    """Verify the API key if one is configured."""
    if WORKER_API_KEY and x_api_key != WORKER_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")


# =============================================================================
# Endpoints
# =============================================================================
@app.get("/health")
def health():
    """Liveness check — Brain pings this to verify the worker is alive."""
    running_jobs = sum(1 for j in jobs.values() if j.status == JobStatus.RUNNING)
    return {
        "status": "ok",
        "worker_id": WORKER_ID,
        "timestamp": datetime.utcnow().isoformat(),
        "running_jobs": running_jobs,
        "max_concurrent": MAX_CONCURRENT_JOBS,
        "total_jobs_processed": len(jobs),
    }


@app.post("/compute")
async def compute(
    body: dict,
    background_tasks: BackgroundTasks,
    x_api_key: Optional[str] = Header(None),
):
    """
    Accept a computation job.

    The body is the same JSON payload that Lambda/Fargate receives:
    {
        "task": {...},
        "output": {...},
        "pipeline": "uuid",
        "alias": "...",
        "user_id": "...",
        "presigned_upload_url": "..."  (optional)
    }

    Returns immediately with a job_id. The computation runs in background.
    Results are reported back to CloudMR Brain via callback.
    """
    verify_api_key(x_api_key)

    # Create job entry
    job_id = str(uuid.uuid4())
    pipeline_id = body.get("pipeline")
    alias = body.get("alias", "")

    job_info = JobInfo(
        job_id=job_id,
        pipeline_id=pipeline_id,
        alias=alias,
        status=JobStatus.PENDING,
        submitted_at=datetime.utcnow().isoformat(),
    )
    jobs[job_id] = job_info

    # Run computation in background
    background_tasks.add_task(run_computation, job_id, body)

    return {
        "status": "accepted",
        "job_id": job_id,
        "pipeline": pipeline_id,
        "message": "Job accepted, processing in background",
    }


@app.get("/jobs")
def list_jobs(x_api_key: Optional[str] = Header(None)):
    """List recent jobs (newest first, max 50)."""
    verify_api_key(x_api_key)
    sorted_jobs = sorted(jobs.values(), key=lambda j: j.submitted_at, reverse=True)
    return {"jobs": [j.dict() for j in sorted_jobs[:50]]}


@app.get("/jobs/{job_id}")
def get_job(job_id: str, x_api_key: Optional[str] = Header(None)):
    """Get status of a specific job."""
    verify_api_key(x_api_key)
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    return jobs[job_id].dict()


# =============================================================================
# Background computation
# =============================================================================
async def run_computation(job_id: str, event: dict):
    """Run the computation in background, respecting concurrency limits."""
    sem = get_semaphore()
    async with sem:
        # Run the blocking do_process in a thread
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _run_computation_sync, job_id, event)


def _run_computation_sync(job_id: str, event: dict):
    """Synchronous wrapper around do_process."""
    job = jobs[job_id]
    job.status = JobStatus.RUNNING
    job.started_at = datetime.utcnow().isoformat()

    try:
        # For local workers, files with type="local" are already on disk.
        # app.py's do_process checks type=="s3" to set NOISE/SIGNAL_AVAILABLE flags.
        # We patch the event to mark local files as available by ensuring
        # the presigned_upload_url is set (so results upload works via presigned URL).
        # If no presigned_upload_url is provided, results stay local.
        
        # Run do_process — it handles downloading S3 files (via presigned URLs),
        # running mrotools.snr, and uploading results.
        result = do_process(event, context=None)

        status_code = result.get("statusCode", 500)
        if status_code == 200:
            job.status = JobStatus.COMPLETED
            job.result = json.loads(result.get("body", "{}"))
        else:
            job.status = JobStatus.FAILED
            job.error = result.get("body", "Unknown error")

    except Exception as e:
        job.status = JobStatus.FAILED
        job.error = traceback.format_exc()
        print(f"[JOB {job_id}] FAILED: {e}")

    finally:
        job.completed_at = datetime.utcnow().isoformat()

    # Report result back to Brain
    _report_to_brain(job)


def _report_to_brain(job: JobInfo):
    """Notify CloudMR Brain of job completion/failure."""
    if not BRAIN_API_URL or not BRAIN_TOKEN:
        print(f"[JOB {job.job_id}] No BRAIN_API_URL/BRAIN_TOKEN configured, skipping callback")
        return

    try:
        headers = {
            "Authorization": f"Bearer {BRAIN_TOKEN}",
            "Content-Type": "application/json",
        }

        if job.status == JobStatus.COMPLETED:
            url = f"{BRAIN_API_URL}/api/pipeline/completed"
            payload = {
                "pipeline": job.pipeline_id,
                "results": job.result,
            }
        else:
            url = f"{BRAIN_API_URL}/api/pipeline/failed"
            payload = {
                "pipeline": job.pipeline_id,
                "error": job.error[:1000] if job.error else "Unknown error",
            }

        resp = requests.post(url, headers=headers, json=payload, timeout=30)
        print(f"[JOB {job.job_id}] Reported {job.status} to Brain: HTTP {resp.status_code}")

    except Exception as e:
        print(f"[JOB {job.job_id}] Failed to report to Brain: {e}")


# =============================================================================
# Main
# =============================================================================
if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", "8000"))
    host = os.environ.get("HOST", "0.0.0.0")
    print(f"Starting MR Optimum Worker on {host}:{port}")
    print(f"  Worker ID: {WORKER_ID}")
    print(f"  Max concurrent jobs: {MAX_CONCURRENT_JOBS}")
    print(f"  Brain API: {BRAIN_API_URL}")
    uvicorn.run(app, host=host, port=port)
