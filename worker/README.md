# MR Optimum — Mode 2 (Self-Hosted Compute)

Run MR Optimum computations on **your own infrastructure**. Zero cost when idle.
Works on AWS, local machines, or SLURM clusters.

## Quick Start (AWS Cloud)

### Prerequisites

- Python 3.9+
- AWS CLI configured (`aws configure --profile your-profile`)
- A CloudMR account (email + password)

### Install dependencies

```bash
pip install boto3 requests
```

### Deploy (GUI)

```bash
python worker/manage.py
```

A window opens. Fill in:
- **AWS Profile** — pick from dropdown (auto-detected from `~/.aws/config`)
- **CloudMR Email** — your cloudmrhub.com login
- **CloudMR Password** — your password
- **Worker Alias** — a friendly name (e.g., "NYU Lab Server")

Click **Deploy**. Done in ~3 minutes.

### Deploy (CLI)

```bash
python worker/manage.py deploy \
  --profile eros \
  --email you@university.edu \
  --alias "My Lab Worker"
```

### After deploying

Open the CloudMR web app, submit a job, and select your Mode 2 worker from the computing unit dropdown. The job runs on your infrastructure.

---

## Managing Your Worker

### Check status

```bash
python worker/manage.py status --profile eros
```

```
  Worker Status
  Stack:    mroptimum-worker-mode2
  Status:   CREATE_COMPLETE
  Endpoint: https://abc123.execute-api.us-east-1.amazonaws.com/Prod
  Health:   OK
  Running tasks: 0
```

### View logs (while a job is running)

```bash
python worker/manage.py logs --profile eros --follow
```

### Check costs

```bash
python worker/manage.py costs --profile eros
```

```
  Cost Estimate (last 30 days)
  Tasks completed:  5
  Tasks running:    0
  Total compute:    23.4 minutes
  Estimated cost:   $0.091
  Idle cost:        $0.00
```

### Tear down (stop all costs)

```bash
python worker/manage.py teardown --profile eros
```

This:
1. Removes your worker from the CloudMR web GUI
2. Deletes all AWS resources
3. Cleans up local config

**After teardown, your cost is $0.00.**

---

## Architecture

```
CloudMR Brain                        Your AWS Account
┌───────────┐   POST /compute   ┌─────────────────────────────┐
│ queue_job │ ────────────────► │  API Gateway (public URL)    │
│           │                   │       ↓                      │
│           │                   │  Lambda dispatcher           │
│           │                   │       ↓                      │
│           │                   │  Fargate RunTask (one-shot)  │
│           │ ◄──────────────── │       ↓                      │
│           │  upload results   │  app.py → mrotools → done    │
└───────────┘                   └─────────────────────────────┘
```

- **API Gateway**: public HTTPS endpoint. $0 when no requests.
- **Lambda dispatcher**: validates the request, launches a Fargate task. ~100ms, costs fractions of a cent.
- **Fargate task**: runs the actual MRI computation (4 vCPU, 16 GB RAM). Starts on demand, exits when done. You pay only for compute time (~$0.23/hour).

### Cost breakdown

| Component | Idle cost | Per-job cost |
|-----------|-----------|--------------|
| API Gateway | $0 | $0.000003 |
| Lambda | $0 | $0.0001 |
| Fargate (4vCPU/16GB) | $0 | ~$0.04–0.50 per job |
| **Total idle** | **$0.00/month** | |

---

## How it works

1. You submit a job from the CloudMR web app
2. CloudMR Brain checks your computing unit and finds the `apiEndpoint`
3. Brain POSTs the job JSON (with presigned URLs for data files) to your API Gateway
4. Your Lambda validates the API key and launches a Fargate task
5. Fargate downloads signal/noise via presigned URLs, runs mrotools, zips results
6. Results are uploaded via a presigned URL back to CloudMR
7. Fargate task exits. Nothing running. $0.

---

## Configuration

Settings are saved to `~/.mroptimum/config.toml` after first deploy:

```toml
profile = "eros"
region = "us-east-1"
email = "you@university.edu"
alias = "My Lab Worker"
endpoint = "https://abc123.execute-api.us-east-1.amazonaws.com/Prod"
api_key = "mro-a1b2c3d4e5f6g7h8"
```

This file is in your home directory (not in the repo) and auto-populates the GUI on next launch.

---

## Supported deployment targets

| Target | Status | How |
|--------|--------|-----|
| AWS Cloud | ✅ Ready | `python manage.py deploy` |
| Local machine | 🚧 Coming | Docker or pip install |
| SLURM cluster | 🚧 Coming | Thin dispatcher on login node |
| Other clouds (GCP, Azure) | 🚧 Planned | Similar to AWS pattern |

---

## Troubleshooting

### "Stack not found"
You haven't deployed yet, or you're using the wrong AWS profile. Check `aws configure list-profiles` and select the correct one.

### "Unable to locate credentials"
Your AWS profile isn't configured. Run `aws configure --profile your-profile` first.

### "Health: UNREACHABLE"
The stack exists but the API Gateway isn't responding. Try `python manage.py status` again — it may be a transient issue. If persistent, check AWS Console > CloudFormation > your stack for errors.

### Job stuck as "pending" in the web GUI
The Fargate task may be starting (takes ~60 seconds for cold start). Check `python manage.py logs --follow` to see progress.

### "Invalid API key" errors
The API key in the Brain database doesn't match your deployed Lambda. Redeploy: `python manage.py deploy` (it re-registers with a fresh key).
