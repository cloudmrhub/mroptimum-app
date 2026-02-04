# MR Optimum Mode 1 Deployment Guide

## Overview

This guide documents the complete Mode 1 deployment workflow for MR Optimum, including local deployment and CI/CD automation via GitHub Actions.

**Mode 1** is the CloudMRHub-managed infrastructure where CloudMRHub owns and operates the computing resources in their AWS account. Users submit jobs through the CloudMR Brain API, which routes them to the Mode 1 infrastructure.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    CloudMR Brain API                          │
│  - Receives job requests from authenticated users             │
│  - Looks up computing units by appId                          │
│  - Routes to Mode 1 Step Function                            │
└──────────────────────────────────────────────────────────────┘
                            ↓
┌──────────────────────────────────────────────────────────────┐
│           Mode 1 (CloudMRHub AWS Account)                     │
│                                                               │
│  ┌────────────────────────────────────────────┐             │
│  │  Step Function (JobChooserStateMachine)    │             │
│  │  - Routes based on task type               │             │
│  │  - Brain calculations → Lambda             │             │
│  │  - Large/complex → Fargate                 │             │
│  └────────────────────────────────────────────┘             │
│           ↓                        ↓                          │
│  ┌──────────────────┐    ┌──────────────────┐               │
│  │  Lambda Function │    │  Fargate Task    │               │
│  │  - Small jobs    │    │  - Large jobs    │               │
│  │  - < 15 min      │    │  - Up to 120GB   │               │
│  │  - < 10GB RAM    │    │  - Hours runtime │               │
│  └──────────────────┘    └──────────────────┘               │
│                                                               │
│  Uses ECR private registry for container images              │
└──────────────────────────────────────────────────────────────┘
```

---

## Components Created

### 1. Docker Images

Two container images built from the same codebase:

| Image | Dockerfile | Registry | Purpose |
|-------|-----------|----------|---------|
| `mroptimum-lambda` | `DockerfileLambda` | Private ECR | Fast jobs in Lambda |
| `mroptimum-fargate` | `DockerfileFargate` | Private ECR | Large jobs in Fargate |

**Key fix applied**: Build with `--provenance=false` to create single-platform manifests compatible with AWS Lambda.

### 2. Infrastructure (SAM/CloudFormation)

- **Root template**: `template.yaml` — orchestrates nested stacks
- **Calculation stack**: `calculation/template.yaml` — defines Lambda, Fargate Task, ECS Cluster, Step Function

Resources created:
- Lambda function using container image
- ECS Cluster for Fargate tasks
- Fargate Task Definition (configurable CPU/memory)
- Step Function State Machine (routes jobs)
- IAM roles (execution, task, Step Function)
- VPC integration (subnets, security groups)

### 3. Deployment Scripts

| Script | Purpose |
|--------|---------|
| `scripts/build-and-push-local.sh` | Build Docker images and push to ECR |
| `scripts/deploy-mode1-local.sh` | Deploy Mode 1 stack locally via SAM |
| `scripts/test-mode1-curl.sh` | Test via CloudMR Brain API (curl) |
| `scripts/test-mode1-request.py` | Test via CloudMR Brain API (Python) |
| `scripts/test-job-execution.sh` | Test Step Function directly |

### 4. CI/CD Workflow

**File**: `.github/workflows/deploy-mode1.yml`

Workflow steps:
1. Checkout code
2. Configure AWS credentials (OIDC role assumption)
3. Build Docker images with `--provenance=false`
4. Push images to private ECR
5. Run SAM build
6. Deploy SAM stack
7. Get State Machine ARN from outputs
8. Register computing unit with CloudMR Brain

### 5. Documentation

- `mode1-deploy.md` — Local deployment instructions
- `MODE1-DEPLOYMENT-GUIDE.md` — This comprehensive guide

---

## Local Deployment Workflow

### Prerequisites

- **Conda environment**: `able`
- **AWS CLI**: Configured with profile having deploy permissions (e.g., `nyu`)
- **Docker**: Installed and running
- **SAM CLI**: Installed (`pip install aws-sam-cli` or `brew install aws-sam-cli`)
- **jq**: For JSON parsing in test scripts

### Step 1: Build and Push Docker Images

This step builds both Lambda and Fargate images and pushes them to your private ECR.

```bash
# Activate conda environment
conda activate able

# Set AWS credentials
export AWS_PROFILE=nyu
export AWS_REGION=us-east-1

# Optional: custom image tag
export IMAGE_TAG=local-$(date +%Y%m%d-%H%M%S)

# Build and push
./scripts/build-and-push-local.sh
```

**What happens**:
- Logs into ECR
- Builds `mroptimum-lambda` from `calculation/src/DockerfileLambda`
- Builds `mroptimum-fargate` from `calculation/src/DockerfileFargate`
- Tags both with `:latest` and custom tag
- Pushes to `<account-id>.dkr.ecr.us-east-1.amazonaws.com/mroptimum-{lambda,fargate}`

**Output**: Image URIs printed at the end

### Step 2: Deploy SAM Stack

This deploys the CloudFormation/SAM stack with Lambda, Fargate, and Step Function.

```bash
# Set network configuration (required for ECS tasks)
export VPC_ID=vpc-xxxxxxxxxxxxx
export SUBNET_ID_1=subnet-0a2008dc8f305421f
export SUBNET_ID_2=subnet-0b5d882b93cc6ff2e
export SECURITY_GROUP_ID=sg-0cb8fdbe5efef42d1

# Set CloudMR Brain integration (optional, for auto-registration)
export CLOUDMR_API_URL=https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod
export CLOUDMR_ADMIN_TOKEN=your_admin_token
export CLOUDMR_BRAIN_STACK=cloudmrhub-brain

# Optional: custom stack name
export STACK_NAME=mroptimum-app-test

# Deploy
./scripts/deploy-mode1-local.sh
```

**What happens**:
- Checks if ECR images exist (fails if Step 1 not done)
- Auto-detects or prompts for VPC/subnets/security group
- Runs `sam deploy` with all parameters
- Gets State Machine ARN from stack outputs
- Optionally registers computing unit with CloudMR Brain (if token provided)

**Output**: State Machine ARN and registration confirmation

### Step 3: Test the Deployment

Three testing options:

#### Option A: Quick curl test (recommended)

```bash
export CLOUDMR_API_URL=https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod
export CLOUDMR_TOKEN=your_jwt_token  # or leave empty to login interactively

./scripts/test-mode1-curl.sh
```

#### Option B: Python test (more detailed logging)

```bash
export CLOUDMR_API_URL=https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod
export CLOUDMR_USERNAME=your_username
export CLOUDMR_PASSWORD=your_password

python scripts/test-mode1-request.py
```

#### Option C: Direct Step Function test (bypasses CloudMR Brain)

```bash
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
  --stack-name mroptimum-app-test \
  --profile nyu \
  --query 'Stacks[0].Outputs[?OutputKey==`CalculationStateMachineArn`].OutputValue' \
  --output text)

./scripts/test-job-execution.sh "$STATE_MACHINE_ARN"
```

**Test flow**:
1. Authenticates with CloudMR Brain
2. Lists available computing units for `mroptimum`
3. Submits a test calculation request
4. Polls status every 5 seconds
5. Reports success/failure with details

---

## GitHub Actions Workflow

### Setup Requirements

#### 1. Create OIDC Role for GitHub Actions

Run the setup script (if not already done):

```bash
./scripts/create-github-oidc-role.sh
```

This creates an IAM role that GitHub Actions can assume without storing long-lived credentials.

#### 2. Configure Repository Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions

Add these secrets:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role ARN for deployment | `arn:aws:iam::xxxxxxxxxxxxx:role/github-actions-deploy` |
| `CLOUDMR_API_URL` | CloudMR Brain API endpoint | `https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod` |
| `CLOUDMR_ADMIN_TOKEN` | Admin token for computing unit registration | `eyJ0eXAiOiJKV1Q...` |
| `CLOUDMR_API_HOST` | CloudMR API host (for CortexHost param) | `f41j488v7j.execute-api.us-east-1.amazonaws.com` |
| `ECS_CLUSTER_NAME` | Name for ECS cluster | `mroptimum-app-cluster` |
| `SUBNET_ID_1` | First subnet for ECS tasks | `subnet-0a2008dc8f305421f` |
| `SUBNET_ID_2` | Second subnet for ECS tasks | `subnet-0b5d882b93cc6ff2e` |
| `SECURITY_GROUP_ID` | Security group for ECS tasks | `sg-0cb8fdbe5efef42d1` |
| `RESULTS_BUCKET` | S3 bucket for results | `cloudmr-brain-results` |
| `FAILED_BUCKET` | S3 bucket for failed jobs | `cloudmr-brain-failed` |
| `DATA_BUCKET` | S3 bucket for input data | `cloudmr-brain-data` |

### Workflow Triggers

The workflow (`.github/workflows/deploy-mode1.yml`) runs on:

- **Push to branches**: `main`, `mode1_mode2`
- **Manual dispatch**: Via GitHub UI (Actions tab → Deploy Mode 1 → Run workflow)

### Workflow Steps

1. **Checkout**: Clone the repository
2. **AWS Auth**: Assume OIDC role (no secrets needed!)
3. **Build Images**: Build Lambda and Fargate images with `--provenance=false`
4. **Push to ECR**: Push to private ECR with `:latest` tag
5. **SAM Build**: Prepare SAM artifacts
6. **SAM Deploy**: Deploy stack with all parameters
7. **Get Outputs**: Extract State Machine ARN
8. **Register**: Register computing unit with CloudMR Brain API

### Monitoring Deployments

- Go to GitHub Actions tab in your repository
- Click on the workflow run
- View logs for each step
- Check for:
  - Image build success
  - ECR push confirmation
  - SAM deployment status
  - State Machine ARN
  - Registration success

---

## Testing Guide

### Understanding Test Flows

**Option 1: Through CloudMR Brain (production-like)**
```
Test Script → CloudMR Brain API → Mode 1 Step Function → Lambda/Fargate → Results
```
This is the real user flow and should be your primary test.

**Option 2: Direct Step Function (debugging)**
```
Test Script → Step Function (direct) → Lambda/Fargate → Results
```
Useful for debugging infrastructure issues without CloudMR Brain.

### Test Script Features

Both test scripts (`test-mode1-curl.sh` and `test-mode1-request.py`) provide:

- **Authentication**: Login or use existing token
- **Computing unit check**: Verify Mode 1 is registered
- **Job submission**: Send test calculation request
- **Status monitoring**: Poll every 5s with timestamps
- **Error reporting**: Show detailed failure information
- **Timeout handling**: Exit after 10 minutes

### Expected Output

#### Success
```
╔═══════════════════════════════════════════════════════════════╗
║   Test Mode 1 via CloudMR Brain API                           ║
╚═══════════════════════════════════════════════════════════════╝

API URL: https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod
App ID:  mroptimum

Checking available computing units...
  - mode1 (cloudmrhub) [DEFAULT]

Submitting test calculation...
✅ Request submitted!
   Pipeline ID: 550e8400-e29b-41d4-a716-446655440000

Monitoring status (Ctrl+C to stop)...

[14:32:10] Status: QUEUED
[14:32:15] Status: RUNNING
[14:33:45] Status: SUCCEEDED

✅ Pipeline SUCCEEDED in 95s

Final status:
{
  "status": "SUCCEEDED",
  "pipelineId": "550e8400-e29b-41d4-a716-446655440000",
  "results": {
    "outputUri": "s3://results-bucket/outputs/..."
  }
}
```

#### Failure
```
[14:32:10] Status: QUEUED
[14:32:15] Status: RUNNING
[14:32:45] Status: FAILED

❌ Pipeline FAILED

Error details:
{
  "status": "FAILED",
  "error": "ExecutionTimeout",
  "message": "Task timed out after 300 seconds"
}
```

---

## Troubleshooting

### Issue: Lambda image error "manifest media type not supported"

**Cause**: Docker BuildKit creates OCI index manifests by default, which AWS Lambda cannot process.

**Solution**: Build with `--provenance=false`:
```bash
docker build --provenance=false -f DockerfileLambda -t mroptimum-lambda .
```

This is already fixed in `scripts/build-and-push-local.sh` and `.github/workflows/deploy-mode1.yml`.

### Issue: ECR login fails

**Solution**: Login manually:
```bash
aws ecr get-login-password --region us-east-1 --profile nyu | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

### Issue: Images not found during deploy

**Error**: `❌ Lambda image not found in ECR`

**Solution**: Run `./scripts/build-and-push-local.sh` first.

### Issue: SAM deploy fails with changeset errors

**Solution**: Add `--no-fail-on-empty-changeset` flag (already in scripts):
```bash
sam deploy ... --no-fail-on-empty-changeset
```

### Issue: Computing unit not registered

**Symptoms**: Test shows no computing units for mroptimum

**Solutions**:
1. Check if `CLOUDMR_ADMIN_TOKEN` was provided during deploy
2. Manually register:
```bash
curl -X POST "${CLOUDMR_API_URL}/api/computing-unit/register" \
  -H "Authorization: Bearer ${CLOUDMR_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "appId": "mroptimum",
    "mode": "mode1",
    "provider": "cloudmrhub",
    "awsAccountId": "xxxxxxxxxxxxx",
    "region": "us-east-1",
    "stateMachineArn": "arn:aws:states:us-east-1:...",
    "resultsBucket": "cloudmr-brain-results",
    "failedBucket": "cloudmr-brain-failed",
    "dataBucket": "cloudmr-brain-data",
    "isDefault": true,
    "isShared": true
  }'
```

### Issue: Test times out (10 minutes)

**Possible causes**:
- Job stuck in QUEUED (Step Function not triggered)
- Job running but taking too long (increase timeout)
- Network issues (check VPC/security group)

**Debug steps**:
1. Check Step Function execution in AWS Console
2. Check Lambda/Fargate logs in CloudWatch
3. Verify network configuration (subnets have internet access)

### Issue: VPC/subnet errors during deploy

**Error**: No default VPC found or subnets don't work

**Solution**: Explicitly set network parameters:
```bash
export VPC_ID=vpc-xxxxx
export SUBNET_ID_1=subnet-aaaa
export SUBNET_ID_2=subnet-bbbb
export SECURITY_GROUP_ID=sg-xxxxx
```

Find available resources:
```bash
# List VPCs
aws ec2 describe-vpcs --profile nyu

# List subnets in VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxx" --profile nyu

# List security groups
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=vpc-xxxxx" --profile nyu
```

---

## Environment Variables Reference

### Local Deployment

```bash
# AWS Configuration
export AWS_PROFILE=nyu              # AWS CLI profile
export AWS_REGION=us-east-1         # AWS region
export STACK_NAME=mroptimum-app-test # CloudFormation stack name

# Network (required for ECS)
export VPC_ID=vpc-xxxxx
export SUBNET_ID_1=subnet-aaaa
export SUBNET_ID_2=subnet-bbbb
export SECURITY_GROUP_ID=sg-xxxxx

# CloudMR Brain Integration (optional)
export CLOUDMR_API_URL=https://...
export CLOUDMR_ADMIN_TOKEN=xxx
export CLOUDMR_BRAIN_STACK=cloudmrhub-brain

# Optional
export IMAGE_TAG=local-20260203-123456  # Custom image tag
```

### Testing

```bash
# CloudMR Brain API
export CLOUDMR_API_URL=https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod

# Option 1: Use token
export CLOUDMR_TOKEN=your_jwt_token

# Option 2: Use credentials (script will login)
export CLOUDMR_USERNAME=your_username
export CLOUDMR_PASSWORD=your_password
```

### GitHub Actions (Secrets)

See "Configure Repository Secrets" section above.

---

## File Structure

```
mroptimum-app/
├── .github/
│   ├── instructions/
│   │   └── mode1_mode2_integration.instructions.md
│   └── workflows/
│       ├── deploy.yml              # Old workflow (reference)
│       └── deploy-mode1.yml        # NEW: Mode 1 workflow
│
├── calculation/
│   ├── template.yaml               # Nested stack (Lambda, Fargate, Step Function)
│   ├── event.json                  # Test event for Step Function
│   ├── ac_brain_multislice.json    # Example calculation payload
│   └── src/
│       ├── app.py                  # Main application code
│       ├── DockerfileLambda        # Lambda container image
│       ├── DockerfileFargate       # Fargate container image
│       └── requirements.txt        # Python dependencies
│
├── scripts/
│   ├── build-and-push-local.sh     # NEW: Build & push images
│   ├── deploy-mode1-local.sh       # NEW: Deploy stack locally
│   ├── test-mode1-curl.sh          # NEW: Test via curl
│   ├── test-mode1-request.py       # NEW: Test via Python
│   └── test-job-execution.sh       # Test Step Function directly
│
├── template.yaml                   # Root SAM template
├── samconfig.toml                  # SAM configuration
├── mode1-deploy.md                 # NEW: Quick deployment guide
└── MODE1-DEPLOYMENT-GUIDE.md       # NEW: This comprehensive guide
```

---

## Next Steps

### For Production Use

1. **Set up GitHub secrets** as documented above
2. **Test the workflow** by pushing to `mode1_mode2` branch
3. **Verify registration** by listing computing units via API
4. **Run integration tests** with real calculation payloads
5. **Monitor CloudWatch logs** for Lambda/Fargate executions
6. **Set up alerts** for failed executions

### For Mode 2 (User-Owned Infrastructure)

Mode 2 allows users to deploy their own computing infrastructure. The deployment package is ready at `mode2-deployment/`:

- Users get the same Docker images from public ECR
- Deploy their own SAM stack in their AWS account
- Register their computing unit with CloudMR Brain
- CloudMR Brain routes their jobs to their infrastructure

See `mode2-deployment/README.md` for details.

---

## Summary of Changes Made

### New Files Created

1. `.github/workflows/deploy-mode1.yml` — CI/CD workflow for Mode 1
2. `scripts/build-and-push-local.sh` — Local image build script
3. `scripts/deploy-mode1-local.sh` — Local deployment script
4. `scripts/test-mode1-curl.sh` — Curl-based test script
5. `scripts/test-mode1-request.py` — Python test script
6. `mode1-deploy.md` — Quick deployment reference
7. `MODE1-DEPLOYMENT-GUIDE.md` — This comprehensive guide

### Key Improvements

- **Docker image fix**: Added `--provenance=false` to ensure Lambda compatibility
- **CI/CD automation**: Complete GitHub Actions workflow with OIDC authentication
- **Local development**: Replicates CI/CD flow for local testing
- **Comprehensive testing**: Multiple test options (curl, Python, direct)
- **Documentation**: Clear guides for both local and CI/CD deployment
- **Error handling**: Improved error messages and validation in scripts

### Infrastructure Components

- Lambda function using container image (for fast jobs)
- Fargate task definition (for large jobs)
- ECS cluster with configurable CPU/memory
- Step Function for job routing
- VPC integration with subnets and security groups
- IAM roles with least-privilege permissions
- CloudMR Brain integration for user job routing

---

## Support and Resources

- **CloudFormation Console**: Monitor stack deployments
- **Step Functions Console**: View execution details and logs
- **CloudWatch Logs**: Lambda and Fargate execution logs
- **ECR Console**: Verify image pushes
- **CloudMR Brain API**: Test job submissions

For issues or questions, check the troubleshooting section above or review CloudWatch logs for execution details.
