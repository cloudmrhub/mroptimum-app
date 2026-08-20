# MR Optimum Worker — Self-Hosted Compute

Run MR Optimum computations on your own hardware. Works anywhere:
Docker, local machine, SLURM cluster, or any cloud.

## Quick Start

```bash
# 1. Set your credentials
export WORKER_API_KEY="your-secret-key"       # You choose this, register it with CloudMR
export BRAIN_API_URL="https://brain.aws.cloudmrhub.com/Prod"
export BRAIN_TOKEN="your-cloudmr-id-token"    # From CloudMR login

# 2. Run with Docker Compose
cd worker/
docker compose up -d

# 3. Register the endpoint with CloudMR Brain
curl -X POST "$BRAIN_API_URL/api/computing-unit/register" \
  -H "Authorization: Bearer $BRAIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "appName": "MR Optimum",
    "mode": "mode_2",
    "provider": "self-hosted",
    "apiEndpoint": "https://your-public-url:8000",
    "apiKey": "your-secret-key",
    "alias": "My Lab Workstation"
  }'
```

## Running Without Docker

```bash
# Install deps
pip install -r requirements.txt

# Run
WORKER_API_KEY="secret" BRAIN_API_URL="https://brain.aws.cloudmrhub.com/Prod" \
  python main.py
```

## Running on SLURM

For HPC clusters, run the worker on the login node (lightweight HTTP server)
and it will submit compute jobs to the SLURM queue:

```bash
# On the login node (in a screen/tmux session)
pip install -r requirements.txt
WORKER_API_KEY="secret" MAX_CONCURRENT_JOBS=4 python main.py
```

Use a reverse proxy or Cloudflare Tunnel to expose it to the internet.

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `WORKER_API_KEY` | Yes | - | Secret key that Brain sends to authenticate requests |
| `BRAIN_API_URL` | Yes | brain.aws.cloudmrhub.com | CloudMR Brain API URL |
| `BRAIN_TOKEN` | Yes | - | Your CloudMR ID token (for reporting results) |
| `WORKER_ID` | No | random | Friendly name for this worker |
| `MAX_CONCURRENT_JOBS` | No | 2 | Parallel job limit |
| `PORT` | No | 8000 | HTTP port |
| `HOST` | No | 0.0.0.0 | Bind address |

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness check (Brain pings this) |
| POST | `/compute` | Submit a computation job |
| GET | `/jobs` | List recent jobs |
| GET | `/jobs/{id}` | Job status |

## Exposing to the Internet

The worker needs to be reachable from CloudMR Brain. Options:

- **Cloud VM**: Use the public IP directly
- **Home/Lab**: Use Cloudflare Tunnel, ngrok, or a reverse proxy
- **SLURM login node**: Usually already has a public IP; use a port

## Architecture

```
CloudMR Brain                    Your Infrastructure
┌───────────┐     POST /compute     ┌──────────────┐
│ queue_job │  ─────────────────►   │ Worker (API) │
│           │                       │              │
│           │  ◄─────────────────   │  app.py      │
│           │  POST /pipeline/done  │  mrotools    │
└───────────┘                       └──────────────┘
```
