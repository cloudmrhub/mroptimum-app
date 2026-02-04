# Mode 1 — Local deploy instructions

Prerequisites
- Use the `able` conda environment: `conda activate able`
- AWS CLI configured for a profile with deploy permissions (e.g. `nyu`).
- Docker installed and you can push to ECR from your machine.

Quick local deploy steps

1. Build and push images to your ECR account (uses `AWS_PROFILE`):

```bash
export AWS_PROFILE=nyu
export AWS_REGION=us-east-1
# optional: provide an explicit image tag
export IMAGE_TAG=local-$(date +%Y%m%d-%H%M%S)
./scripts/build-and-push-local.sh
```

2. Deploy the SAM stack locally (will read images from ECR):

```bash
# Provide network info if not using default VPC/subnets
export VPC_ID=vpc-xxxxxxxx
export SUBNET_ID_1=subnet-aaaaaaa
export SUBNET_ID_2=subnet-bbbbbbb
export SECURITY_GROUP_ID=sg-xxxxxx

# Optional: CLOUDMR settings for auto-registration
export CLOUDMR_API_URL=https://xxxx.execute-api.us-east-1.amazonaws.com/Prod
export CLOUDMR_ADMIN_TOKEN=your_admin_token

# Deploy
./scripts/deploy-mode1-local.sh
```

Notes & troubleshooting
- If images are missing, run `./scripts/build-and-push-local.sh` first.
- Script will attempt to auto-detect a default VPC and subnets; set them explicitly in CI.
- The local script uses `sam deploy`. Make sure SAM CLI is installed.

## Testing the deployment

After deploying Mode 1, test the full end-to-end flow through CloudMR Brain API.

### Option 1: Using the Python test script

```bash
# Activate able conda environment
conda activate able

# Set CloudMR credentials
export CLOUDMR_API_URL=https://xxx.execute-api.us-east-1.amazonaws.com/Prod
export CLOUDMR_USERNAME=your_username
export CLOUDMR_PASSWORD=your_password

# Run test
python scripts/test-mode1-request.py
```

### Option 2: Using curl (faster)

```bash
export CLOUDMR_API_URL=https://xxxx.execute-api.us-east-1.amazonaws.com/Prod
export CLOUDMR_TOKEN=your_jwt_token  # or leave empty to login interactively

./scripts/test-mode1-curl.sh
```

### Option 3: Direct Step Function test (bypasses CloudMR Brain)

If you want to test the Step Function directly without going through CloudMR Brain:

```bash
# Get the State Machine ARN
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
  --stack-name mroptimum-app-test \
  --profile nyu \
  --query 'Stacks[0].Outputs[?OutputKey==`CalculationStateMachineArn`].OutputValue' \
  --output text)

# Run test
./scripts/test-job-execution.sh "$STATE_MACHINE_ARN"
```

### What to expect

1. **Request submitted** — You'll get a pipeline ID
2. **Status updates** — The script polls every 5s and shows status changes (QUEUED → RUNNING → SUCCEEDED)
3. **Success** — Full response with results location
4. **Failure** — Error details from the execution

## Secrets and GitHub

The CI workflow `./.github/workflows/deploy-mode1.yml` expects these repository secrets:
- `AWS_DEPLOY_ROLE_ARN` (role to assume for deployment)
- `CLOUDMR_API_URL` and `CLOUDMR_ADMIN_TOKEN` (for registration)
- `CLOUDMR_API_HOST` (used as `CortexHost` parameter in SAM)
- `ECS_CLUSTER_NAME`, `SUBNET_ID_1`, `SUBNET_ID_2`, `SECURITY_GROUP_ID`
- `RESULTS_BUCKET`, `FAILED_BUCKET`, `DATA_BUCKET` (used when registering computing unit)
