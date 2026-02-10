# Mode 2 Deployment & Registration Guide

## Overview

**Mode 2** deploys MR Optimum compute infrastructure in **YOUR AWS account**. You pay for the compute, and data stays in your S3 buckets. Jobs are routed from CloudMR Brain to your infrastructure.

---

## Quick Start

### Prerequisites

1. **AWS Account** with admin access
2. **AWS CLI** configured (`aws configure`)
3. **CloudMR Account** with email/password

### One-Command Deployment

```bash
# Option 1: Using deploy-mode2.sh (automatic registration included in template)
cd mode2-deployment/
./deploy-mode2.sh
```

**OR**

```bash
# Option 2: Manual deployment + registration
cd mode2-deployment/
./deploy-mode2.sh  # Deploy the stack
cd ..
./scripts/register-mode2.sh  # Register the computing unit
```

---

## Detailed Step-by-Step

### Step 1: Deploy the CloudFormation Stack

The Mode 2 template creates:
- ✅ S3 buckets (data, results, failed)
- ✅ ECS Cluster with Fargate
- ✅ Lambda functions for small jobs
- ✅ Step Function state machine
- ✅ IAM roles with proper permissions
- ✅ Automatic registration Lambda (triggered on stack creation)

**Interactive Mode:**

```bash
cd mode2-deployment/
./deploy-mode2.sh
```

You'll be prompted for:
1. CloudMR user token (get from CloudMR Brain profile)
2. VPC selection
3. Subnet selection

**Non-Interactive Mode:**

```bash
export AWS_PROFILE=myprofile
export AWS_REGION=us-east-1

cd mode2-deployment/
./deploy-mode2.sh \
    --stack-name my-mroptimum \
    --region us-east-1 \
    --api-url https://api.cloudmrhub.com
```

**Manual CloudFormation Deployment:**

```bash
# Set your CloudMR credentials
export CLOUDMR_API_URL="https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="yourpassword"

# Get your token
CLOUDMR_TOKEN=$(curl -s -X POST "$CLOUDMR_API_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$CLOUDMR_EMAIL\",\"password\":\"$CLOUDMR_PASSWORD\"}" | jq -r '.id_token')

# Deploy the stack
aws cloudformation deploy \
    --template-file mode2-deployment/template-mode2.yaml \
    --stack-name mroptimum-mode2 \
    --region us-east-1 \
    --parameter-overrides \
        CloudMRApiUrl="$CLOUDMR_API_URL" \
        CloudMRUserToken="$CLOUDMR_TOKEN" \
        VpcId="vpc-xxxxxxxxx" \
        SubnetId1="subnet-xxxxxxxxx" \
        SubnetId2="subnet-xxxxxxxxx" \
        ImageTag="latest" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND
```

### Step 2: Register Computing Unit (if not auto-registered)

The Mode 2 template includes a Lambda function that automatically registers the computing unit with CloudMR Brain when the stack is created. However, if you need to manually register:

```bash
# Set environment variables
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="yourpassword"
export CLOUDMR_API_URL="https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"
export MODE="mode_2"
export STACK_NAME="mroptimum-mode2"
export REGION="us-east-1"

# Run registration script
./scripts/register-computing-unit.sh
```

**What the registration does:**
1. Logs in to CloudMR Brain
2. Detects State Machine ARN from your CloudFormation stack
3. Detects S3 bucket names
4. Registers computing unit as `mode_2` with `provider=user`
5. Verifies registration was successful

### Step 3: Verify Deployment

```bash
# Check stack status
aws cloudformation describe-stacks \
    --stack-name mroptimum-mode2 \
    --query 'Stacks[0].StackStatus'

# Get stack outputs (State Machine ARN, bucket names)
aws cloudformation describe-stacks \
    --stack-name mroptimum-mode2 \
    --query 'Stacks[0].Outputs'

# List registered computing units
export ID_TOKEN=$(curl -s -X POST "$CLOUDMR_API_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$CLOUDMR_EMAIL\",\"password\":\"$CLOUDMR_PASSWORD\"}" | jq -r '.id_token')

curl -s -H "Authorization: Bearer $ID_TOKEN" \
  "$CLOUDMR_API_URL/api/computing-unit/list?app_name=MR%20Optimum" | jq .
```

You should see two computing units:
- **Mode 1** (CloudMRHub managed) - `mode: "mode_1"`, `provider: "cloudmrhub"`
- **Mode 2** (Your account) - `mode: "mode_2"`, `provider: "user"`

---

## Architecture Comparison

| Component | Mode 1 (CloudMRHub) | Mode 2 (Your Account) |
|-----------|---------------------|----------------------|
| **S3 Buckets** | CloudMRHub account | YOUR account |
| **State Machine** | CloudMRHub account | YOUR account |
| **Lambda/Fargate** | CloudMRHub account | YOUR account |
| **Costs** | Paid by CloudMRHub | **Paid by YOU** |
| **Data Location** | CloudMRHub S3 | Your S3 |
| **Compute Control** | Shared resources | Dedicated resources |

---

## How Mode 2 Works

```
User submits job through CloudMR Brain UI
            ↓
CloudMR Brain API looks up user's computing unit
            ↓
Finds Mode 2 unit → Assumes cross-account role in YOUR account
            ↓
Invokes YOUR Step Function
            ↓
YOUR Lambda/Fargate runs the computation
            ↓
Results written to YOUR S3 bucket
            ↓
Callback Lambda notifies CloudMR Brain (job complete)
            ↓
User downloads results via presigned URL (from YOUR S3)
```

### Cross-Account Access

The Mode 2 template creates a **cross-account role** that allows CloudMR Brain to:
1. Invoke your Step Function
2. Generate presigned URLs for result downloads

This role has **limited permissions** (only what's needed for job orchestration).

---

## Environment Variables Reference

### For Deployment (deploy-mode2.sh)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AWS_PROFILE` | No | default | AWS CLI profile |
| `AWS_REGION` | No | us-east-1 | AWS region |
| `CLOUDMR_API_URL` | Yes | - | CloudMR Brain API URL |

### For Registration (register-computing-unit.sh)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CLOUDMR_EMAIL` | Yes | - | Your CloudMR email |
| `CLOUDMR_PASSWORD` | Yes | - | Your CloudMR password |
| `CLOUDMR_API_URL` | Yes | - | CloudMR Brain API URL |
| `MODE` | No | Auto-detect | `mode_2` |
| `STACK_NAME` | No | mroptimum-mode2 | CloudFormation stack name |
| `REGION` | No | us-east-1 | AWS region |
| `STATE_MACHINE_ARN` | No | Auto-detect | Step Function ARN |

---

## Cost Estimation (Mode 2)

All costs are charged to **YOUR AWS account**:

| Resource | Estimated Cost |
|----------|---------------|
| Lambda (small jobs) | $0.20 per 1M requests + compute |
| Fargate (large jobs) | $0.04/vCPU/hour + $0.004/GB/hour |
| S3 Storage | $0.023/GB/month |
| S3 API Calls | Minimal (GET/PUT) |
| Step Functions | $0.025 per 1K transitions |

**Example**: A job using 4 vCPU + 8GB RAM for 10 minutes:
- Fargate compute: (4 × $0.04 + 8 × $0.004) × (10/60) = ~$0.03
- S3 storage: Negligible for transient data
- **Total per job: ~$0.03 - $0.05**

---

## Troubleshooting

### 1. Stack Creation Fails

**Check CloudFormation events:**
```bash
aws cloudformation describe-stack-events \
    --stack-name mroptimum-mode2 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

**Common issues:**
- VPC/subnets don't have internet access (needed for ECR pulls)
- Invalid CloudMR token
- Missing IAM permissions

### 2. Registration Fails

**Check the error message:**
```bash
./scripts/register-computing-unit.sh 2>&1 | tee registration.log
```

**Common issues:**
- State Machine ARN not found → Check stack outputs
- Invalid CloudMR credentials
- User not authorized (need active CloudMR account)

### 3. Jobs Not Routing to Mode 2

**Verify registration:**
```bash
curl -s -H "Authorization: Bearer $ID_TOKEN" \
  "$CLOUDMR_API_URL/api/computing-unit/list?app_name=MR%20Optimum" | jq .
```

**Check:**
- Computing unit shows `mode: "mode_2"`
- `provider: "user"`
- `awsAccountId` matches YOUR account

### 4. Fargate Tasks Fail to Start

**Check ECS task logs:**
```bash
aws ecs list-tasks --cluster mroptimum-mode2-cluster
aws ecs describe-tasks --cluster mroptimum-mode2-cluster --tasks <task-arn>
```

**Common issues:**
- Security group blocking internet access
- ECR image pull fails (check execution role permissions)
- Insufficient Fargate capacity in region

---

## Cleanup

To delete all Mode 2 resources:

```bash
# 1. Delete CloudFormation stack
aws cloudformation delete-stack --stack-name mroptimum-mode2

# 2. Unregister computing unit (optional - will be cleaned up by CloudMR Brain)
# Use CloudMR Brain UI to remove the computing unit

# 3. Verify deletion
aws cloudformation describe-stacks --stack-name mroptimum-mode2
```

**Note**: S3 buckets may need to be emptied before stack deletion completes.

---

## Security Considerations

### Cross-Account Role Permissions

The Mode 2 template creates a role with **minimal permissions**:
- ✅ Start Step Function executions
- ✅ Read execution status
- ✅ Generate presigned URLs for result downloads
- ❌ NO access to modify/delete resources
- ❌ NO access to IAM, CloudFormation, or other services

### Data Privacy

In Mode 2:
- ✅ Input data stays in YOUR S3
- ✅ Results stay in YOUR S3
- ✅ CloudMR Brain only stores metadata (job status, links)
- ✅ You control retention policies

### Network Security

- Fargate tasks run in YOUR VPC
- Security group allows outbound only (for ECR pulls)
- No inbound access required

---

## Advanced Configuration

### Custom Docker Images

If you want to use your own modified images:

1. Build and push to YOUR ECR:
```bash
aws ecr create-repository --repository-name mroptimum-custom
docker build -t mroptimum-custom .
docker tag mroptimum-custom:latest $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/mroptimum-custom:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/mroptimum-custom:latest
```

2. Modify `template-mode2.yaml` to reference your ECR repository

### Custom Resource Limits

Edit Fargate task definition in `template-mode2.yaml`:
```yaml
FargateTaskDefinition:
  Properties:
    Cpu: "8192"  # 8 vCPU
    Memory: "16384"  # 16 GB
```

---

## Next Steps

1. ✅ Deploy Mode 2 stack
2. ✅ Verify registration
3. ✅ Submit test job via CloudMR Brain UI
4. ✅ Monitor costs in AWS Cost Explorer
5. ✅ Set up billing alerts

For questions or issues, contact CloudMRHub support.

---

## MR Optimum Mode 2 Deployment (User-Owned)

### Prerequisites
- AWS CLI, SAM CLI, jq, curl installed
- AWS account with permissions for CloudFormation, Lambda, ECS, ECR, S3
- Access to CloudMR ECR images (cross-account pull enabled)
- VPC with at least 2 subnets and a security group
- CloudMR Brain API endpoint URL
- CloudMR admin credentials (email/password)

### Required Files
- `template-mode2.yaml` (root SAM template)
- `calculation/template.yaml` (nested calculation stack)
- `scripts/deploy-and-register-mode2.sh` (main deploy script)
- `scripts/register-computing-unit.sh` (registration logic)

### Deployment Steps

1. **Set AWS Credentials**
   ```bash
   aws configure --profile eros
   ```

2. **Run the Deployment Script**
   ```bash
   ./scripts/deploy-and-register-mode2.sh \
       --email 'your@email.com' \
       --password 'yourpassword' \
       --profile eros
   ```
   Options:
   - `--region` (default: us-east-1)
   - `--stack-name` (default: mroptimum-mode2)
   - `--data-bucket`, `--results-bucket`, `--failed-bucket` (defaults to Mode 1 bucket names)

3. **Script Workflow**
   - Validates tools and credentials
   - Logs in to CloudMR Brain
   - Resolves ECR image URIs
   - Detects or prompts for VPC, subnets, security group
   - Deploys the stack using `template-mode2.yaml`
   - Registers the computing unit with CloudMR Brain
   - Outputs stack details and registration status

4. **Troubleshooting**
   - If deployment fails, check CloudFormation events:
     ```bash
     aws cloudformation describe-stack-events --stack-name mroptimum-mode2 --profile eros --region us-east-1
     ```
   - Common issues:
     - ECR cross-account pull not enabled
     - Lambda memory size > 3008 MB (fix in calculation/template.yaml)
     - Invalid AWS credentials

5. **Cleanup**
   To delete the stack:
   ```bash
   aws cloudformation delete-stack --stack-name mroptimum-mode2 --profile eros --region us-east-1
   ```

---

**Summary:**
- Use `deploy-and-register-mode2.sh` for all-in-one deployment and registration
- Ensure bucket names match Mode 1 (or override as needed)
- All infrastructure runs in your AWS account
- Registered as Mode 2 computing unit in CloudMR Brain

---

For advanced automation, you can adapt this workflow to GitHub Actions or other CI/CD tools.
