---
applyTo: '**'
---
# Mode 1 Deployment Guide

This guide explains how to deploy MR Optimum in **Mode 1** (CloudMRHub-managed infrastructure).

## Overview

Mode 1 deployment creates computing infrastructure in CloudMRHub's AWS account that processes jobs submitted through CloudMR Brain. The deployment consists of:

1. **Docker Images** - Lambda and Fargate container images pushed to ECR
2. **SAM Stack** - CloudFormation resources (Step Function, Lambda, ECS Cluster, Fargate Task)
3. **Computing Unit Registration** - Register the deployed infrastructure with CloudMR Brain API

---

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2.x | AWS operations |
| SAM CLI | v1.x | Deploy CloudFormation stacks |
| Docker | 20.x+ | Build container images |
| jq | 1.6+ | JSON processing in scripts |
| curl | any | API calls |

### AWS Requirements

- Valid AWS credentials with permissions for:
  - ECR (create repos, push images)
  - CloudFormation (create/update stacks)
  - Lambda, ECS, Step Functions, IAM
  - S3 (read bucket info)
- VPC with at least 2 subnets (for Fargate tasks)
- Security group allowing outbound internet access

### CloudMR Brain Requirements

- CloudMR Brain API endpoint URL
- Admin user account (member of "Admins" Cognito group)
- Valid ID token for authentication

---

## Environment Variables

### AWS Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AWS_PROFILE` | No | `nyu` | AWS CLI profile name |
| `AWS_REGION` | No | `us-east-1` | AWS region for deployment |
| `AWS_ACCOUNT_ID` | Auto | - | Detected from credentials |

### Network Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `VPC_ID` | CI only | Auto-detect | VPC ID for ECS tasks |
| `SUBNET_ID_1` | CI only | Auto-detect | First subnet for Fargate |
| `SUBNET_ID_2` | CI only | Auto-detect | Second subnet for Fargate |
| `SECURITY_GROUP_ID` | CI only | Auto-detect | Security group for tasks |

> **Note**: In interactive mode, these are auto-detected or prompted. In CI mode (GitHub Actions), they must be set.

### Stack Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `STACK_NAME` | No | `mroptimum-app-test` | CloudFormation stack name |
| `CLOUDMR_BRAIN_STACK` | No | `cloudmrhub-brain` | CloudMR Brain stack name (for imports) |

### CloudMR Brain API

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CLOUDM_MR_BRAIN` | Yes | - | CloudMR Brain API endpoint URL |
| `ID_TOKEN` | Yes* | - | Cognito ID token for API authentication |
| `ADMIN_ID_TOKEN` | Yes* | - | Admin ID token (can be same as ID_TOKEN) |

> *At least one of `ID_TOKEN` or `ADMIN_ID_TOKEN` must be set for registration.

### Mode 1 Outputs (Set by Deployment)

These are automatically set after deployment:

| Variable | Description |
|----------|-------------|
| `STATE_MACHINE_ARN` | ARN of deployed Step Function |
| `DATA_BUCKET` | S3 bucket for input data |
| `RESULTS_BUCKET` | S3 bucket for job results |
| `FAILED_BUCKET` | S3 bucket for failed job artifacts |

---

## Deployment Workflow

### Quick Start (All-in-One)

```bash
# 1. Set required environment variables
export AWS_PROFILE='nyu'
export CLOUDM_MR_BRAIN='https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod'

# 2. Get an admin token (login to CloudMR Brain)
export ID_TOKEN=$(curl -s -X POST "$CLOUDM_MR_BRAIN/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email": "your@email.com", "password": "yourpassword"}' | jq -r '.id_token // .idToken')

# 3. Run the all-in-one script
./scripts/deploy-and-register-mode1.sh
```

### Step-by-Step Deployment

#### Step 1: Build and Push Docker Images

```bash
# Set AWS profile
export AWS_PROFILE='nyu'

# Build and push images to ECR
./scripts/build-and-push-local.sh
```

This script:
- Logs into ECR
- Builds `mroptimum-lambda` and `mroptimum-fargate` images
- Pushes images with `:latest` and timestamped tags

**Important**: Uses `--provenance=false` flag to ensure Lambda compatibility.

#### Step 2: Deploy SAM Stack

```bash
# Set optional network params (or let script auto-detect)
export VPC_ID='vpc-xxxxxxxxx'
export SUBNET_ID_1='subnet-xxxxxxxxx'
export SUBNET_ID_2='subnet-xxxxxxxxx'
export SECURITY_GROUP_ID='sg-xxxxxxxxx'

# Deploy the stack
./scripts/deploy-mode1-local.sh
```

This script:
- Validates AWS credentials
- Checks ECR images exist
- Auto-detects or prompts for network configuration
- Deploys SAM template via CloudFormation
- Writes outputs to `exports.mode1.sh`

#### Step 3: Register Computing Unit

```bash
# Source the deployment outputs
source exports.mode1.sh

# Set API credentials
export CLOUDM_MR_BRAIN='https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod'
export ADMIN_ID_TOKEN='eyJ...'  # Your admin token

# Register with CloudMR Brain
./scripts/register-mode1.sh
```

This script:
- Creates CloudApp "MR Optimum" if not exists
- Checks for existing Mode1 computing unit
- Registers new computing unit with Step Function ARN and bucket names
- Verifies registration

---

## Scripts Reference

### `scripts/build-and-push-local.sh`

Builds and pushes Docker images to ECR.

**Environment Variables:**
- `AWS_PROFILE` - AWS CLI profile (default: `nyu`)
- `AWS_REGION` - AWS region (default: `us-east-1`)
- `IMAGE_TAG` - Custom image tag (default: `local-YYYYMMDD-HHMMSS`)

**Output:**
- `mroptimum-lambda:latest` in ECR
- `mroptimum-fargate:latest` in ECR

---

### `scripts/deploy-mode1-local.sh`

Deploys the Mode 1 SAM stack.

**Environment Variables:**
- `AWS_PROFILE`, `AWS_REGION`, `STACK_NAME`
- `VPC_ID`, `SUBNET_ID_1`, `SUBNET_ID_2`, `SECURITY_GROUP_ID` (CI mode)
- `CLOUDMR_BRAIN_STACK` - For cross-stack references

**Output:**
- Creates `exports.mode1.sh` with discovered values:
  ```bash
  export AWS_ACCOUNT_ID='123456789012'
  export STATE_MACHINE_ARN='arn:aws:states:...'
  export DATA_BUCKET='cloudmr-data-...'
  export RESULTS_BUCKET='cloudmr-results-...'
  export FAILED_BUCKET='cloudmr-failed-...'
  ```

---

### `scripts/register-mode1.sh`

Registers the computing unit with CloudMR Brain.

**Required Environment Variables:**
- `CLOUDM_MR_BRAIN` - API endpoint URL
- `ADMIN_ID_TOKEN` - Admin authentication token
- `AWS_ACCOUNT_ID` - AWS account ID
- `STATE_MACHINE_ARN` - Deployed Step Function ARN
- `DATA_BUCKET`, `RESULTS_BUCKET`, `FAILED_BUCKET` - S3 bucket names

**Optional:**
- `APP_NAME` - CloudApp name (default: `MR Optimum`)
- `REGION` - AWS region (default: `us-east-1`)

---

### `scripts/deploy-and-register-mode1.sh`

All-in-one wrapper that runs all steps sequentially.

**What it does:**
1. Sources `exports.sh` for credentials
2. Runs `deploy-mode1-local.sh`
3. Sources `exports.mode1.sh` for outputs
4. Updates `exports.sh` with new values
5. Runs `register-mode1.sh`
6. Verifies registration

---

## Configuration Files

### `exports.sh`

Central configuration file for environment variables. Example:

```bash
# CloudMR Brain API
export CLOUDM_MR_BRAIN='https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod'

# Authentication (set these before sourcing)
# export ID_TOKEN='eyJ...'
# export ADMIN_ID_TOKEN='eyJ...'

# AWS Configuration
export AWS_PROFILE='nyu'
export AWS_ACCOUNT_ID='469266894233'

# Mode 1 Resources (set by deployment)
export STATE_MACHINE_ARN='arn:aws:states:us-east-1:469266894233:stateMachine:...'
export DATA_BUCKET='cloudmr-data-cloudmrhub-brain-us-east-1'
export RESULTS_BUCKET='cloudmr-results-cloudmrhub-brain-us-east-1'
export FAILED_BUCKET='cloudmr-failed-cloudmrhub-brain-us-east-1'
```

### `exports.mode1.sh`

Generated by `deploy-mode1-local.sh` with deployment outputs. This file is auto-generated and should not be manually edited.

---

## CI/CD Integration

### Overview

The CI/CD workflow (`.github/workflows/deploy-mode1.yml`) automates the entire Mode 1 deployment:

1. **Build Images** - Builds Docker images and pushes to ECR
2. **Deploy Stack** - Deploys SAM CloudFormation stack
3. **Register CU** - Registers computing unit with CloudMR Brain
4. **Summary** - Reports deployment status

### Triggering the Workflow

The workflow triggers on:
- Push to `main` or `mode1_mode2` branches (when `calculation/**`, `template.yaml`, or workflow files change)
- Manual dispatch via GitHub Actions UI

### Setting Up GitHub Actions

#### Step 1: Create OIDC Role for GitHub Actions

```bash
# Run from the repository root
./scripts/create-github-oidc-role.sh cloudmrhub mroptimum-app
```

This creates an IAM role that GitHub Actions can assume via OIDC (no long-lived credentials needed).

#### Step 2: Configure GitHub Secrets

Required secrets for the workflow:

| Secret | Description | Example |
|--------|-------------|---------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role ARN for OIDC auth | `arn:aws:iam::469266894233:role/GitHubActionsRole-mroptimum-app` |
| `SUBNET_ID_1` | First subnet for Fargate | `subnet-0a2008dc8f305421f` |
| `SUBNET_ID_2` | Second subnet for Fargate | `subnet-0b5d882b93cc6ff2e` |
| `SECURITY_GROUP_ID` | Security group for ECS tasks | `sg-0cb8fdbe5efef42d1` |
| `CLOUDMR_API_URL` | CloudMR Brain API endpoint | `https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod` |

**Authentication secrets** (choose one approach):

| Approach | Secrets | Notes |
|----------|---------|-------|
| **Recommended: Auto-refresh** | `CLOUDMR_ADMIN_EMAIL` + `CLOUDMR_ADMIN_PASSWORD` | Workflow logs in and gets fresh token each run. Never expires. |
| Legacy: Static token | `CLOUDMR_ADMIN_TOKEN` | Must be refreshed manually when token expires (~1 hour). |

Optional secrets:

| Secret | Description | Default |
|--------|-------------|---------|
| `CLOUDMR_API_HOST` | API hostname (without https://) | `api.cloudmrhub.com` |

#### Step 3: Set Secrets via GitHub CLI

```bash
# Required infrastructure secrets
gh secret set AWS_DEPLOY_ROLE_ARN --repo cloudmrhub/mroptimum-app --body "arn:aws:iam::469266894233:role/GitHubActionsRole-mroptimum-app"
gh secret set SUBNET_ID_1 --repo cloudmrhub/mroptimum-app --body "subnet-0a2008dc8f305421f"
gh secret set SUBNET_ID_2 --repo cloudmrhub/mroptimum-app --body "subnet-0b5d882b93cc6ff2e"
gh secret set SECURITY_GROUP_ID --repo cloudmrhub/mroptimum-app --body "sg-0cb8fdbe5efef42d1"
gh secret set CLOUDMR_API_URL --repo cloudmrhub/mroptimum-app --body "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"

# Authentication (recommended: email + password for auto-refresh)
gh secret set CLOUDMR_ADMIN_EMAIL --repo cloudmrhub/mroptimum-app --body "eros.montin@nyulangone.org"
gh secret set CLOUDMR_ADMIN_PASSWORD --repo cloudmrhub/mroptimum-app  # prompts for password interactively
```

### Manual Workflow Dispatch Options

When triggering manually via GitHub Actions UI, you can:

- **Skip Docker build**: Use existing images in ECR (faster deployment)
- **Skip registration**: Only deploy infrastructure without registering with CloudMR Brain

### GitHub Actions Secrets

Configure these secrets in your GitHub repository:

| Secret | Description |
|--------|-------------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role ARN for OIDC authentication |
| `VPC_ID` | VPC ID for ECS tasks |
| `SUBNET_ID_1` | First subnet ID |
| `SUBNET_ID_2` | Second subnet ID |
| `SECURITY_GROUP_ID` | Security group ID |
| `CLOUDMR_API_URL` | CloudMR Brain API URL |
| `CLOUDMR_ADMIN_TOKEN` | Admin token for registration |

### Workflow Example

```yaml
name: Deploy Mode 1

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: us-east-1
      
      - name: Build and push images
        run: ./scripts/build-and-push-local.sh
      
      - name: Deploy stack
        env:
          VPC_ID: ${{ secrets.VPC_ID }}
          SUBNET_ID_1: ${{ secrets.SUBNET_ID_1 }}
          SUBNET_ID_2: ${{ secrets.SUBNET_ID_2 }}
          SECURITY_GROUP_ID: ${{ secrets.SECURITY_GROUP_ID }}
        run: ./scripts/deploy-mode1-local.sh
      
      - name: Register computing unit
        env:
          CLOUDM_MR_BRAIN: ${{ secrets.CLOUDMR_API_URL }}
          ADMIN_ID_TOKEN: ${{ secrets.CLOUDMR_ADMIN_TOKEN }}
        run: |
          source exports.mode1.sh
          ./scripts/register-mode1.sh
```

---

## Troubleshooting

### AWS Credentials Expired

```
❌ Unable to get AWS caller identity
```

**Fix**: Re-authenticate with AWS SSO:
```bash
aws sso login --profile nyu
```

### ECR Images Not Found

```
❌ Lambda image not found in ECR
```

**Fix**: Build and push images first:
```bash
./scripts/build-and-push-local.sh
```

### Computing Unit Registration 403

```
{"message": "Invalid key=value pair..."}
```

**Possible causes:**
1. Token expired - get a fresh token
2. Wrong API path - ensure using `/api/computing-unit/register`
3. User not in Admins group

**Fix**: Get a fresh token:
```bash
export ID_TOKEN=$(curl -s -X POST "$CLOUDM_MR_BRAIN/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email": "your@email.com", "password": "yourpassword"}' | jq -r '.id_token // .idToken')
export ADMIN_ID_TOKEN="$ID_TOKEN"
```

### Stack Deployment Fails

Check CloudFormation events:
```bash
aws cloudformation describe-stack-events \
  --stack-name mroptimum-app-test \
  --profile nyu \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

---

## Verification

### Check Deployed Resources

```bash
# Get stack outputs
aws cloudformation describe-stacks \
  --stack-name mroptimum-app-test \
  --profile nyu \
  --query 'Stacks[0].Outputs'

# Check Step Function
aws stepfunctions describe-state-machine \
  --state-machine-arn "$STATE_MACHINE_ARN" \
  --profile nyu
```

### Verify Computing Unit Registration

```bash
# List registered computing units
curl -s -H "Authorization: Bearer $ADMIN_ID_TOKEN" \
  "$CLOUDM_MR_BRAIN/api/computing-unit/list?appName=MR%20Optimum" | jq .
```

### Test Job Execution

```bash
# Start a test execution
aws stepfunctions start-execution \
  --state-machine-arn "$STATE_MACHINE_ARN" \
  --input '{"test": true}' \
  --profile nyu
```

---

## Current Deployment Status

| Resource | Value |
|----------|-------|
| Stack Name | `mroptimum-app-test` |
| AWS Account | `469266894233` |
| Region | `us-east-1` |
| State Machine | `mroptimum-app-test-CalculationApp-...-JobChooser` |
| Computing Unit ID | `205e2772-9021-42aa-a4b9-79b345b84b93` |
| CloudApp | `MR Optimum` (appId: `d8cecb2c-2aee-4bfa-a794-630279285104`) |

### S3 Buckets

| Bucket Type | Name |
|-------------|------|
| Data | `cloudmr-data-cloudmrhub-brain-us-east-1` |
| Results | `cloudmr-results-cloudmrhub-brain-us-east-1` |
| Failed | `cloudmr-failed-cloudmrhub-brain-us-east-1` |
