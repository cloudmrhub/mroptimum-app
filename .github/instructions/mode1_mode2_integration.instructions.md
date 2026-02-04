---
applyTo: '**'
---
# MR Optimum Mode 1 & Mode 2 Architecture

## Overview

MR Optimum has been refactored to support two deployment modes that integrate with CloudMR Brain:

- **Mode 1 (CloudMR Managed)**: Infrastructure owned and operated by CloudMRHub. Users submit jobs through the CloudMR Brain API, which routes them to CloudMRHub's AWS account.
- **Mode 2 (User-Owned)**: Users deploy their own computing infrastructure in their AWS account. CloudMR Brain routes jobs to the user's Step Function.

Both modes use the same core computation code but differ in who owns/pays for the infrastructure.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CloudMR Brain                                  │
│  (API Gateway + Lambda + DynamoDB)                                      │
│  - Receives job requests from users                                      │
│  - Looks up computing unit (Mode 1 or Mode 2)                           │
│  - Invokes the appropriate Step Function                                 │
└─────────────────────────────────────────────────────────────────────────┘
                    │                              │
                    ▼                              ▼
    ┌──────────────────────────┐    ┌──────────────────────────┐
    │   Mode 1 (CloudMRHub)    │    │   Mode 2 (User Account)  │
    │   AWS Account            │    │   AWS Account            │
    │   ─────────────────      │    │   ─────────────────      │
    │   • Step Function        │    │   • Step Function        │
    │   • Lambda (small jobs)  │    │   • Lambda (small jobs)  │
    │   • Fargate (large jobs) │    │   • Fargate (large jobs) │
    │   • ECS Cluster          │    │   • ECS Cluster          │
    └──────────────────────────┘    └──────────────────────────┘
```

---

## What Has Been Implemented

### 1. Docker Images (Lambda & Fargate)

Two Docker images are built from the same codebase:

| Image | Dockerfile | Purpose |
|-------|-----------|---------|
| `mroptimum-lambda` | `DockerfileLambda` | Small/fast jobs (< 15 min, < 10GB RAM) |
| `mroptimum-fargate` | `DockerfileFargate` | Large jobs (up to 120GB RAM, hours) |

**Critical Fix Applied**: Docker BuildKit creates multi-platform manifests by default, which AWS Lambda cannot process. The build script uses `--provenance=false` to force single-platform manifest creation.

### 2. ECR Repositories

Two private ECR repositories store the images:
- `xxxxxxxxxxxxx.dkr.ecr.us-east-1.amazonaws.com/mroptimum-lambda`
- `xxxxxxxxxxxxx.dkr.ecr.us-east-1.amazonaws.com/mroptimum-fargate`

### 3. CloudFormation/SAM Templates

| File | Purpose |
|------|---------|
| `template.yaml` | Root stack - orchestrates nested stacks |
| `calculation/template.yaml` | Nested stack - Lambda, Fargate Task, Step Function |

### 4. Step Function (JobChooserStateMachine)

Routes jobs based on task type:
- Brain calculations → Lambda
- Large/complex calculations → Fargate

### 5. Scripts Created

| Script | Purpose |
|--------|---------|
| `scripts/build-and-push-local.sh` | Build Docker images and push to ECR |
| `scripts/deploy-mode1-local.sh` | Deploy Mode 1 stack and register with CloudMR Brain |
| `scripts/create-github-oidc-role.sh` | Create IAM role for GitHub Actions |
| `scripts/test-job-execution.sh` | Test job execution through Step Function |

### 6. CI/CD Workflow

GitHub Actions workflow at `.github/workflows/deploy.yml` automates:
1. Build and push Docker images
2. Deploy SAM stack
3. Register computing unit with CloudMR Brain

---

## Mode 1 Deployment (Completed)

### Current State: ✅ DEPLOYED

**Stack Name**: `xxxxx`  
**AWS Account**: `xxxxxxxxxxxxx`  
**Region**: `us-east-1`

### Deployed Resources

- **State Machine**: Successfully created
- **Lambda Function**: Using container image from ECR
- **ECS Cluster**: `xxxxx-cluster`
- **Fargate Task Definition**: Configured for large jobs
- **IAM Roles**: Lambda execution role, ECS task role, Step Function role

### Network Configuration

| Resource | Value |
|----------|-------|
| VPC | `vpc-xxxxx` (cmr-calculation00-vpc) |
| Subnet 1 | `subnet-xxxxx` |
| Subnet 2 | `subnet-xxxxx` |
| Security Group | `sg-xxxxx` |

### CloudMR Brain Integration

| Parameter | Value |
|-----------|-------|
| API URL | `https://xxxx.execute-api.us-east-1.amazonaws.com/Prod` |
| Brain Stack | `cloudmrhub-brain` |

### Pending: Registration

The computing unit needs to be registered with CloudMR Brain:

```bash
export AWS_PROFILE=nyu
export CLOUDMR_ADMIN_TOKEN=your_admin_token
export CLOUDMR_API_URL=https://xxxx.execute-api.us-east-1.amazonaws.com/Prod

./scripts/deploy-mode1-local.sh
```

---

## Mode 2 Deployment (Ready for Users)

### Package Created

A deployment package exists at `mode2-deployment/` containing:

```
mode2-deployment/
├── README.md              # User instructions
├── template.yaml          # SAM template for user deployment
├── calculation/
│   └── template.yaml      # Nested stack
└── scripts/
    ├── deploy.sh          # One-click deployment
    └── register.sh        # Register with CloudMR Brain
```

### User Deployment Steps

1. User clones/downloads the mode2-deployment package
2. Runs `./scripts/deploy.sh` with their AWS credentials
3. Runs `./scripts/register.sh` with their CloudMR API key
4. CloudMR Brain now routes their jobs to their own infrastructure

---

## Environment Variables Reference

### For Local Development (deploy-mode1-local.sh)

```bash
# Required for CI/CD (non-interactive mode):
export VPC_ID=vpc-xxxxx
export SUBNET_ID_1=subnet-xxxxx
export SUBNET_ID_2=subnet-xxxxx
export SECURITY_GROUP_ID=sg-xxxxx
export CLOUDMR_API_URL=https://xxxx.execute-api.us-east-1.amazonaws.com/Prod
export CLOUDMR_ADMIN_TOKEN=your_token

# Optional (have defaults):
export AWS_PROFILE=nyu
export AWS_REGION=us-east-1
export STACK_NAME=xxxxx
export CLOUDMR_BRAIN_STACK=xxxx-brain
```

### For GitHub Actions

Secrets to configure in GitHub repository:

| Secret | Description |
|--------|-------------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role ARN for OIDC authentication |
| `VPC_ID` | VPC for ECS tasks |
| `SUBNET_ID_1` | First subnet |
| `SUBNET_ID_2` | Second subnet |
| `SECURITY_GROUP_ID` | Security group |
| `CLOUDMR_API_URL` | CloudMR Brain API URL |
| `CLOUDMR_ADMIN_TOKEN` | Admin token for registration |

---

## Next Steps

### Immediate (Mode 1)

1. **Register Computing Unit**: Run deploy script with `CLOUDMR_ADMIN_TOKEN` set
2. **Test Job Execution**: Use `scripts/test-job-execution.sh` to verify end-to-end flow
3. **Set up GitHub Actions**: Configure OIDC role and repository secrets

### Future (Mode 2)

1. **Package for Distribution**: Finalize mode2-deployment package
2. **Documentation**: Create user guide for Mode 2 deployment
3. **Self-Registration Portal**: Allow users to register their computing units through web UI

---

## Troubleshooting

### Lambda Image Error: "manifest media type not supported"

**Cause**: Docker BuildKit creates OCI index manifests by default.  
**Solution**: Build with `--provenance=false`:

```bash
docker build --provenance=false -f DockerfileLambda -t mroptimum-lambda .
```

### ECR Login Issues

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin xxxxxxxxxxxxx.dkr.ecr.us-east-1.amazonaws.com
```

### Stack Deployment Fails

Check CloudFormation events:
```bash
aws cloudformation describe-stack-events --stack-name mroptimum-app-test --profile nyu
```

---

## File Structure

```
mroptimum-app/
├── template.yaml                    # Root SAM template
├── calculation/
│   ├── template.yaml               # Nested stack (Lambda, Fargate, Step Function)
│   └── src/
│       ├── app.py                  # Main application code
│       ├── DockerfileLambda        # Lambda container image
│       ├── DockerfileFargate       # Fargate container image
│       └── requirements.txt
├── scripts/
│   ├── build-and-push-local.sh     # Build & push Docker images
│   ├── deploy-mode1-local.sh       # Deploy Mode 1 stack
│   ├── create-github-oidc-role.sh  # Create GitHub OIDC IAM role
│   └── test-job-execution.sh       # Test job execution
├── .github/
│   └── workflows/
│       └── deploy.yml              # CI/CD workflow
└── mode2-deployment/               # Package for Mode 2 users
    ├── README.md
    ├── template.yaml
    └── scripts/
```

---

## Commands Quick Reference

### Build and Push Images
```bash
AWS_PROFILE=nyu ./scripts/build-and-push-local.sh
```

### Deploy Mode 1 (Interactive)
```bash
AWS_PROFILE=nyu ./scripts/deploy-mode1-local.sh
```

### Deploy Mode 1 (Non-Interactive)
```bash
export AWS_PROFILE=nyu
export VPC_ID=vpc-xxxxx
export SUBNET_ID_1=subnet-xxxxx
export SUBNET_ID_2=subnet-xxxxx
export SECURITY_GROUP_ID=sg-xxxxx
export CLOUDMR_API_URL=https://xxxx.execute-api.us-east-1.amazonaws.com/Prod
export CLOUDMR_ADMIN_TOKEN=your_token
./scripts/deploy-mode1-local.sh
```

### Check Stack Status
```bash
aws cloudformation describe-stacks --stack-name mroptimum-app-test --profile nyu --query 'Stacks[0].StackStatus'
```

### Get State Machine ARN
```bash
aws cloudformation describe-stacks --stack-name mroptimum-app-test --profile nyu --query 'Stacks[0].Outputs[?OutputKey==`CalculationStateMachineArn`].OutputValue' --output text
```