# MR Optimum Backend - Dual-Mode Architecture

MR Optimum is a scientific computing application for SNR calculations on MRI data. This repository contains the backend compute infrastructure that supports two deployment modes.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          CloudMR Platform                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────┐      ┌─────────────────┐     ┌─────────────────┐   │
│  │   mroptimum-    │      │   cloudmr-      │     │   mroptimum-    │   │
│  │     webgui      │◀────▶│     brain       │◀───▶│     app         │   │
│  │                 │      │                 │     │                 │   │
│  │  React/TS       │      │  Python/SAM     │     │  Python/Docker  │   │
│  │  (YOUR account) │      │  (YOUR account) │     │  (Mode 1 or 2)  │   │
│  └─────────────────┘      └─────────────────┘     └─────────────────┘   │
│                                   │                       │              │
│                                   ▼                       ▼              │
│                           ┌─────────────┐         ┌─────────────────┐   │
│                           │  DynamoDB   │         │  Step Functions │   │
│                           │  - Users    │         │  ▼               │   │
│                           │  - Pipelines│         │  Lambda/Fargate  │   │
│                           │  - Computing│         │  ▼               │   │
│                           │    Units    │         │  S3 Results      │   │
│                           └─────────────┘         └─────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Dual-Mode Deployment

### Mode 1: CloudMRHub Managed (Default)

- **Compute runs in CloudMRHub's AWS account**
- Uses CloudMRHub's S3 buckets
- CloudMRHub pays for compute/storage
- Auto-deployed via CI/CD on push to `main`
- Available to all users as default option

### Mode 2: User-Owned

- **Compute runs in USER's AWS account**
- Uses USER's S3 buckets
- User pays for compute/storage
- User deploys using provided template
- Gives dedicated resources and data sovereignty

## Repository Structure

```
mroptimum-app/
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD for Mode 1
├── calculation/
│   ├── template.yaml           # Nested stack for compute resources
│   └── src/
│       ├── app.py              # Main computation logic
│       ├── DockerfileLambda    # Lambda container image
│       └── DockerfileFargate   # Fargate container image
├── mode2-deployment/
│   ├── template-mode2.yaml     # CloudFormation for user deployment
│   └── deploy-mode2.sh         # User deployment script
├── scripts/
│   ├── create-ecr-repos.sh     # Setup ECR repositories
│   ├── create-github-oidc-role.sh  # Setup GitHub Actions role
│   └── setup-github-secrets.sh # Configure GitHub secrets
├── template.yaml               # Main SAM template (Mode 1)
├── samconfig.toml              # SAM deployment config
└── README.md
```

## Quick Start

### Mode 1 Setup (CloudMRHub Team)

1. **Create ECR Repositories**
   ```bash
   ./scripts/create-ecr-repos.sh
   ```

2. **Setup GitHub Actions OIDC Role**
   ```bash
   ./scripts/create-github-oidc-role.sh cloudmrhub mroptimum-app
   ```

3. **Configure GitHub Secrets**
   ```bash
   ./scripts/setup-github-secrets.sh cloudmrhub/mroptimum-app
   ```

4. **Push to main branch**
   - CI/CD will automatically:
     - Build Docker images
     - Push to private ECR (Mode 1) and public ECR (Mode 2)
     - Deploy SAM stack
     - Register computing unit with CloudMR Brain

### Mode 2 Setup (End Users)

1. **Download Deployment Package**
   ```bash
   # Download from CloudMRHub or clone this repo
   cd mode2-deployment
   ```

2. **Run Deployment Script**
   ```bash
   ./deploy-mode2.sh
   ```
   
   The script will:
   - Prompt for CloudMR credentials
   - Create S3 buckets in your account
   - Deploy compute infrastructure (Lambda + Fargate)
   - Auto-register with CloudMR Brain

3. **Select Mode 2 in Web UI**
   - Go to MR Optimum web interface
   - Select "Mode 2 - User Owned" in settings
   - Run computations in your AWS account

## CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/deploy.yml`) performs:

1. **Build Phase**
   - Builds Lambda Docker image
   - Builds Fargate Docker image
   - Tags with git SHA and `latest`

2. **Push Phase**
   - Pushes to private ECR (for Mode 1 use)
   - Pushes to public ECR (for Mode 2 users to pull)

3. **Deploy Phase**
   - Runs `sam build`
   - Runs `sam deploy` with parameters

4. **Register Phase**
   - Gets State Machine ARN from stack outputs
   - POSTs to CloudMR Brain `/api/computing-unit/register`

## Computing Unit Registration

### Mode 1 Registration (Automatic via CI/CD)

```json
{
  "appId": "mroptimum",
  "mode": "mode1",
  "provider": "cloudmrhub",
  "awsAccountId": "123456789012",
  "region": "us-east-1",
  "stateMachineArn": "arn:aws:states:...",
  "resultsBucket": "cloudmr-results",
  "failedBucket": "cloudmr-failed",
  "dataBucket": "cloudmr-data",
  "isDefault": true,
  "isShared": true
}
```

### Mode 2 Registration (Automatic via CloudFormation)

```json
{
  "appId": "mroptimum",
  "mode": "mode2",
  "provider": "user-owned",
  "awsAccountId": "USER_ACCOUNT_ID",
  "region": "us-east-1",
  "stateMachineArn": "arn:aws:states:...",
  "crossAccountRoleArn": "arn:aws:iam::USER_ACCOUNT:role/...",
  "externalId": "cloudmr-USER_ACCOUNT-mroptimum",
  "resultsBucket": "user-results-bucket",
  "failedBucket": "user-failed-bucket",
  "dataBucket": "user-data-bucket"
}
```

## Cross-Account Architecture (Mode 2)

```
┌──────────────────────────────┐     ┌──────────────────────────────┐
│    CloudMRHub Account        │     │      User's Account          │
├──────────────────────────────┤     ├──────────────────────────────┤
│                              │     │                              │
│  cloudmr-brain               │     │  mroptimum-mode2 stack       │
│  ├─ /task/queue API ─────────┼────▶│  ├─ CrossAccountRole         │
│  │    (AssumeRole)           │     │  │    (trusts CloudMRHub)    │
│  │                           │     │  │                           │
│  │                           │     │  ├─ Step Functions           │
│  │                           │     │  │    └─ Lambda/Fargate      │
│  │                           │     │  │                           │
│  │                           │     │  ├─ Results Bucket           │
│  │                           │◀────┼──│    (S3 event → callback)  │
│  ├─ /pipeline/completed API  │     │  │                           │
│  │    (receives callback)    │     │  └─ Failed Bucket            │
│  │                           │     │                              │
│  ├─ /data/presign API ───────┼────▶│  (generates presigned URLs)  │
│  │    (AssumeRole)           │     │                              │
│                              │     │                              │
└──────────────────────────────┘     └──────────────────────────────┘
```

## Docker Image Strategy

Images are built once by CloudMRHub CI/CD and distributed via:

| Repository | Purpose | Access |
|------------|---------|--------|
| `private.ecr.aws/mroptimum-lambda` | Mode 1 Lambda | CloudMRHub only |
| `private.ecr.aws/mroptimum-fargate` | Mode 1 Fargate | CloudMRHub only |
| `public.ecr.aws/cloudmrhub/mroptimum-lambda` | Mode 2 Lambda | All users |
| `public.ecr.aws/cloudmrhub/mroptimum-fargate` | Mode 2 Fargate | All users |

**Mode 2 users do NOT need to build Docker images** - they pull pre-built images from public ECR.

## Environment Variables

### Compute Functions

| Variable | Description |
|----------|-------------|
| `ResultsBucketName` | S3 bucket for successful results |
| `FailedBucketName` | S3 bucket for failed jobs |
| `CLOUDMR_API_URL` | CloudMR Brain API URL |
| `EXECUTION_MODE` | `mode1` or `mode2` |

## Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role for GitHub Actions OIDC |
| `CLOUDMR_API_HOST` | CloudMR Brain hostname |
| `CLOUDMR_API_URL` | Full CloudMR Brain URL |
| `CLOUDMR_ADMIN_TOKEN` | Admin token for registration |
| `ECS_CLUSTER_NAME` | ECS cluster name |
| `SUBNET_ID_1` | First VPC subnet |
| `SUBNET_ID_2` | Second VPC subnet |
| `SECURITY_GROUP_ID` | Security group for ECS |
| `RESULTS_BUCKET` | Mode 1 results bucket |
| `FAILED_BUCKET` | Mode 1 failed bucket |
| `DATA_BUCKET` | Mode 1 data bucket |

## Troubleshooting

### Mode 1 Issues

**CI/CD fails at image push:**
- Check ECR repositories exist
- Verify AWS_DEPLOY_ROLE_ARN has ECR permissions

**Stack deployment fails:**
- Check cloudmr-brain stack exports exist
- Verify networking parameters are valid

### Mode 2 Issues

**User deployment fails:**
- Check VPC has public subnets with internet access
- Verify CloudMR token is valid

**Jobs don't start:**
- Check cross-account role trust policy
- Verify external ID matches

**Results not appearing:**
- Check S3 event notifications are enabled
- Verify callback Lambda has network access

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes
4. Test locally with `sam local invoke`
5. Submit a pull request

## License

Copyright © CloudMRHub. All rights reserved.
