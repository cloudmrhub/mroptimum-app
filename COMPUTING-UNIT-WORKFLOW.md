# MR Optimum Computing Unit Registration & Job Submission Guide

## Overview

This guide covers the complete workflow for registering MR Optimum with CloudMR Brain and submitting jobs through the new computing unit architecture.

### What's New

The CloudMR Brain API has been refactored to support **multi-mode computing units**:

- **Mode 1 (CloudMRHub Managed)**: Infrastructure owned by CloudMRHub, runs in `262361552878`
- **Mode 2 (User-Owned)**: Infrastructure owned by user, runs in user's AWS account

Each CloudApp can have multiple computing units registered, one per mode.

---

## Quick Start

### For Mode 1 (Recommended)

```bash
# 1. Register computing unit
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="yourpassword"
export CLOUDMR_API_URL="https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"
./scripts/register-computing-unit.sh

# 2. Submit a job
./scripts/submit-job.sh
```

### For Mode 2

```bash
# 1. Register with custom mode
export MODE="mode_2"
./scripts/register-computing-unit.sh

# 2. Submit job selecting mode 2
export MODE="mode_2"
./scripts/submit-job.sh
```

---

## Task 1: Register Computing Unit

### Script: `scripts/register-computing-unit.sh`

Registers MR Optimum as a computing unit with CloudMR Brain. Handles:
- CloudMR Brain authentication
- State Machine ARN detection (CloudFormation)
- Provider determination (cloudmrhub vs user)
- Computing unit registration
- Unit verification

### Prerequisites

1. **CloudMR Brain credentials**:
   ```bash
   export CLOUDMR_EMAIL="your@email.com"
   export CLOUDMR_PASSWORD="yourpassword"
   export CLOUDMR_API_URL="https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"
   ```

2. **AWS credentials** (for State Machine ARN detection):
   ```bash
   aws configure  # or set AWS_PROFILE
   ```

3. **Deployed SAM Stack**:
   ```bash
   export STACK_NAME="mroptimum-app"
   export REGION="us-east-1"
   ```

### Usage

#### Mode 1 (CloudMRHub Managed) - Default

```bash
# Auto-detect everything
./scripts/register-computing-unit.sh
```

**What happens:**
1. Logs into CloudMR Brain
2. Retrieves State Machine ARN from CloudFormation
3. Detects AWS account (262361552878 = Mode 1 provider: cloudmrhub)
4. Registers computing unit with mode_1
5. Lists all computing units for verification

#### Mode 2 (User-Owned)

```bash
export MODE="mode_2"
./scripts/register-computing-unit.sh
```

**What happens:**
1. Logs into CloudMR Brain
2. Retrieves State Machine ARN from CloudFormation
3. Detects AWS account (user account = Mode 2 provider: user)
4. Registers computing unit with mode_2
5. Lists all computing units for verification

#### Custom State Machine ARN

If auto-detection fails:

```bash
export STATE_MACHINE_ARN="arn:aws:states:us-east-1:123456789012:stateMachine:..."
./scripts/register-computing-unit.sh
```

#### Custom Parameters

```bash
export APP_NAME="My App"
export MODE="mode_1"
export AWS_ACCOUNT_ID="262361552878"
export REGION="us-east-1"
export STACK_NAME="my-stack"
./scripts/register-computing-unit.sh
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_NAME` | `MR Optimum` | CloudApp name in CloudMR Brain |
| `MODE` | `mode_1` | Computing unit mode |
| `AWS_ACCOUNT_ID` | Auto-detect | AWS account ID |
| `REGION` | `us-east-1` | AWS region |
| `STATE_MACHINE_ARN` | Auto-detect | Step Function ARN |
| `STACK_NAME` | `mroptimum-app` | CloudFormation stack name |
| `CLOUDMR_API_URL` | **Required** | CloudMR Brain API endpoint |
| `CLOUDMR_EMAIL` | **Required** | CloudMR user email |
| `CLOUDMR_PASSWORD` | **Required** | CloudMR user password |

### Output

Successful registration produces:
```
[SUCCESS] Logged in as: your@email.com (user_id: abc-123)
[SUCCESS] State Machine ARN: arn:aws:states:us-east-1:262361552878:stateMachine:...
[SUCCESS] Mode 1 (CloudMRHub Managed) - Provider: cloudmrhub
[SUCCESS] Computing unit registered: 550e8400-e29b-41d4-a716-446655440000

[INFO] Available computing units:
[
  {
    "computingUnitId": "550e8400-e29b-41d4-a716-446655440000",
    "mode": "mode_1",
    "provider": "cloudmrhub",
    "awsAccountId": "262361552878"
  }
]
```

### Troubleshooting

#### "State Machine ARN not found"

```bash
# Verify stack exists
aws cloudformation describe-stacks --stack-name mroptimum-app

# Check outputs
aws cloudformation describe-stacks --stack-name mroptimum-app \
  --query 'Stacks[0].Outputs'

# Provide ARN manually
export STATE_MACHINE_ARN="arn:aws:..."
```

#### "Login failed"

```bash
# Verify credentials
echo "Email: $CLOUDMR_EMAIL"
echo "Password: (not shown)"
echo "API URL: $CLOUDMR_API_URL"

# Test login manually
curl -X POST "$CLOUDMR_API_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$CLOUDMR_EMAIL\",\"password\":\"$CLOUDMR_PASSWORD\"}"
```

#### "AWS credentials expired"

```bash
aws sso login --profile your-profile
export AWS_PROFILE="your-profile"
```

---

## Task 2: Submit Jobs

### Script: `scripts/submit-job.sh`

Complete job submission workflow:
1. **Login** → Authenticate with CloudMR Brain
2. **Query** → List available computing units
3. **Select** → Choose mode or specific computing unit
4. **Queue** → Submit job to CloudMR Brain
5. **Verify** → Get execution ARN and status

### Prerequisites

1. **CloudMR Brain credentials**:
   ```bash
   export CLOUDMR_EMAIL="your@email.com"
   export CLOUDMR_PASSWORD="yourpassword"
   export CLOUDMR_API_URL="https://..."
   ```

2. **Registered computing unit** (run Task 1 first)

### Usage

#### Interactive Mode (Recommended)

```bash
./scripts/submit-job.sh
```

**Prompts:**
1. CloudMR Email
2. CloudMR Password
3. Mode selection menu:
   - Option 1: mode_1 (CloudMRHub Managed)
   - Option 2: mode_2 (User Owned)
   - Option 3: Choose specific computing unit by ID

#### By Mode (Pattern 1 & 2)

```bash
# Submit to Mode 1 (CloudMRHub Managed)
export MODE="mode_1"
./scripts/submit-job.sh

# Submit to Mode 2 (User Owned)
export MODE="mode_2"
./scripts/submit-job.sh
```

#### By Computing Unit ID (Pattern 3)

```bash
export COMPUTING_UNIT_ID="550e8400-e29b-41d4-a716-446655440000"
./scripts/submit-job.sh
```

#### Non-Interactive (for CI/CD)

```bash
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="yourpassword"
export CLOUDMR_API_URL="https://..."
export MODE="mode_1"
export INTERACTIVE="false"
./scripts/submit-job.sh
```

#### Custom Job Definition

```bash
export TASK_DEFINITION='{"task_type":"custom","parameters":{"key":"value"}}'
export PIPELINE_ALIAS="my-custom-job"
./scripts/submit-job.sh
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLOUDMR_EMAIL` | **Required** | CloudMR user email |
| `CLOUDMR_PASSWORD` | **Required** | CloudMR user password |
| `CLOUDMR_API_URL` | **Required** | CloudMR Brain API endpoint |
| `APP_NAME` | `CAMRIE` | CloudApp name |
| `MODE` | Auto-select | Computing unit mode (mode_1 or mode_2) |
| `COMPUTING_UNIT_ID` | Auto-select | Specific computing unit UUID |
| `PIPELINE_ALIAS` | Auto-generated | Job name/alias |
| `TASK_DEFINITION` | Brain calc | Job task definition (JSON) |
| `INTERACTIVE` | `true` | Enable interactive prompts |

### Output

Successful job submission:

```
════════════════════════════════════════
Step 2: Authenticating with CloudMR Brain
════════════════════════════════════════

[INFO] Logging in as: your@email.com
[SUCCESS] Authentication successful

════════════════════════════════════════
Step 3: Querying Available Computing Units
════════════════════════════════════════

[INFO] Fetching computing units for app: CAMRIE
[SUCCESS] Found 1 computing unit(s)

[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "mode": "mode_1",
    "provider": "cloudmrhub",
    "account": "262361552878"
  }
]

════════════════════════════════════════
Step 6: Queueing Job with CloudMR Brain
════════════════════════════════════════

[INFO] Queueing by mode: mode_1

Job payload:
{
  "cloudapp_name": "CAMRIE",
  "alias": "mr-opt-job-1707142020",
  "mode": "mode_1",
  "task": {
    "task_type": "brain_calculation",
    "parameters": {
      "input_format": "nifti",
      "output_format": "nifti"
    }
  }
}

[SUCCESS] Job queued successfully!
[INFO] Execution ARN: arn:aws:states:us-east-1:262361552878:execution:...
[INFO] Pipeline UUID: pipeline-uuid-abc-123
[INFO] Computing Unit: 550e8400-e29b-41d4-a716-446655440000

════════════════════════════════════════
Job Submission Complete
════════════════════════════════════════

Job Details:
  App Name: CAMRIE
  Pipeline Alias: mr-opt-job-1707142020
  Mode: mode_1
  Execution ARN: arn:aws:states:us-east-1:262361552878:execution:...

Next Steps:
  1. Monitor job execution in CloudMR Brain
  2. Check results in S3 buckets
  3. Use execution ARN to track status:
     aws stepfunctions describe-execution --execution-arn "arn:aws:..."
```

### Job Queueing Patterns

#### Pattern 1: Queue by Mode (mode_1)

```bash
curl -X POST "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod/api/pipeline/queue_job" \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "cloudapp_name": "CAMRIE",
    "alias": "my-job",
    "mode": "mode_1",
    "task": {"task_type": "brain_calculation"}
  }'
```

**Response:**
```json
{
  "pipelineId": "abc-123",
  "executionArn": "arn:aws:states:us-east-1:262361552878:execution:...",
  "computingUnit": {
    "computingUnitId": "550e8400-...",
    "mode": "mode_1"
  }
}
```

#### Pattern 2: Queue by Mode (mode_2)

```bash
curl -X POST "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod/api/pipeline/queue_job" \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "cloudapp_name": "CAMRIE",
    "alias": "my-job",
    "mode": "mode_2",
    "task": {"task_type": "brain_calculation"}
  }'
```

#### Pattern 3: Queue by Computing Unit ID

```bash
curl -X POST "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod/api/pipeline/queue_job" \
  -H "Authorization: Bearer $ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "cloudapp_name": "CAMRIE",
    "alias": "my-job",
    "computing_unit_id": "550e8400-e29b-41d4-a716-446655440000",
    "task": {"task_type": "brain_calculation"}
  }'
```

### Troubleshooting

#### "No computing units found"

```bash
# Verify registration completed
./scripts/register-computing-unit.sh

# Check manually
curl -H "Authorization: Bearer $ID_TOKEN" \
  "https://.../api/computing-unit/list?app_name=CAMRIE"
```

#### "Job queueing failed"

```bash
# Check IAM permissions on CloudMR Brain side
# CloudMR Brain's QueueJobFunction needs:
#   - logs:CreateLogGroup
#   - logs:CreateLogStream
#   - logs:PutLogEvents
#   - states:StartExecution (on state machine)
#   - s3:PutObject (on result buckets)

# Verify step function exists and is accessible
aws stepfunctions describe-state-machine \
  --state-machine-arn "arn:aws:states:us-east-1:262361552878:stateMachine:..."
```

#### "Execution shows no progress"

```bash
# Check step function execution status
aws stepfunctions describe-execution \
  --execution-arn "arn:aws:states:us-east-1:262361552878:execution:..."

# Check logs
aws logs tail /aws/lambda/cloudmr-queuejob --follow

# Check S3 input bucket
aws s3 ls cloudmr-data-cloudmrhub-brain-us-east-1/
```

---

## Complete Workflow Example

```bash
#!/bin/bash

# Setup
export CLOUDMR_EMAIL="eros.montin@nyulangone.org"
export CLOUDMR_PASSWORD="tYeY4Huw...remaining_password"
export CLOUDMR_API_URL="https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"

# Step 1: Register Computing Unit (one-time)
echo "=== Registering Computing Unit ==="
./scripts/register-computing-unit.sh

# Step 2: Submit Jobs (repeatedly)
echo ""
echo "=== Submitting Jobs ==="

# Job 1: Using mode
export MODE="mode_1"
./scripts/submit-job.sh

# Job 2: Interactive
./scripts/submit-job.sh

# Job 3: By computing unit ID
export COMPUTING_UNIT_ID="550e8400-e29b-41d4-a716-446655440000"
./scripts/submit-job.sh
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Register and Submit Job

on: [push]

jobs:
  register:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Register computing unit
        env:
          CLOUDMR_EMAIL: ${{ secrets.CLOUDMR_EMAIL }}
          CLOUDMR_PASSWORD: ${{ secrets.CLOUDMR_PASSWORD }}
          CLOUDMR_API_URL: ${{ secrets.CLOUDMR_API_URL }}
        run: ./scripts/register-computing-unit.sh
      
      - name: Submit job
        env:
          CLOUDMR_EMAIL: ${{ secrets.CLOUDMR_EMAIL }}
          CLOUDMR_PASSWORD: ${{ secrets.CLOUDMR_PASSWORD }}
          CLOUDMR_API_URL: ${{ secrets.CLOUDMR_API_URL }}
          MODE: mode_1
          INTERACTIVE: "false"
        run: ./scripts/submit-job.sh
```

### Local Development

```bash
# Store credentials in exports_user.sh (not committed)
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="yourpassword"
export CLOUDMR_API_URL="https://..."

# Register once
./scripts/register-computing-unit.sh

# Submit jobs
./scripts/submit-job.sh
```

---

## Architecture Reference

### Registration Flow

```
┌─────────────────┐
│ register-cu.sh  │
└────────┬────────┘
         │
    ┌────▼─────────────────────────┐
    │ 1. Login to CloudMR Brain    │ (POST /auth/login)
    └────┬─────────────────────────┘
         │
    ┌────▼──────────────────────────┐
    │ 2. Get State Machine ARN       │ (CloudFormation)
    └────┬──────────────────────────┘
         │
    ┌────▼──────────────────────────┐
    │ 3. Determine Provider          │ (Account check)
    │    - cloudmrhub (Mode 1)       │
    │    - user (Mode 2)             │
    └────┬──────────────────────────┘
         │
    ┌────▼─────────────────────────────┐
    │ 4. Register Computing Unit       │ (POST /api/computing-unit/register)
    │    - Mode: mode_1 or mode_2      │
    │    - Provider: cloudmrhub/user   │
    │    - StateMachineArn             │
    │    - Buckets                     │
    └────┬─────────────────────────────┘
         │
    ┌────▼─────────────────┐
    │ 5. List Units        │ (GET /api/computing-unit/list)
    │    (verification)    │
    └──────────────────────┘
```

### Job Submission Flow

```
┌──────────────────┐
│ submit-job.sh    │
└────────┬─────────┘
         │
    ┌────▼─────────────────┐
    │ 1. Login             │ (POST /auth/login)
    └────┬─────────────────┘
         │
    ┌────▼──────────────────────┐
    │ 2. Query Units           │ (GET /api/computing-unit/list)
    └────┬──────────────────────┘
         │
    ┌────▼─────────────────────────┐
    │ 3. Select Unit               │ (Interactive or env var)
    │    - Mode: mode_1 or mode_2  │
    │    - OR: computing_unit_id   │
    └────┬─────────────────────────┘
         │
    ┌────▼──────────────────────────┐
    │ 4. Prepare Task Definition    │
    └────┬──────────────────────────┘
         │
    ┌────▼──────────────────────────────────┐
    │ 5. Queue Job                         │ (POST /api/pipeline/queue_job)
    │    - cloudapp_name                   │
    │    - alias                           │
    │    - mode OR computing_unit_id       │
    │    - task definition                 │
    └────┬──────────────────────────────────┘
         │
    ┌────▼──────────────────────────┐
    │ 6. Get Execution Details      │
    │    - executionArn             │
    │    - pipelineId               │
    │    - computingUnit            │
    └──────────────────────────────┘
```

### Computing Unit Selection Priority

```
┌─────────────────────────┐
│ Job Submission Request  │
└────────────┬────────────┘
             │
        ┌────▼────────────────────────┐
        │ Priority 1:                  │
        │ computing_unit_id provided?  │
        │ (explicit selection)         │
        └─┬──────────────────────────┬─┘
         YES                         NO
          │                           │
          └─────────────────┬─────────┘
                            │
                      ┌─────▼──────────┐
                      │ Priority 2:    │
                      │ mode provided? │
                      └─┬──────────┬──┘
                       YES        NO
                        │          │
                        └────┬─────┘
                             │
                      ┌──────▼────────┐
                      │ Priority 3:   │
                      │ Auto-select   │
                      │ mode_1        │
                      └───────────────┘
```

---

## Support & Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Invalid key=value pair" | Special chars in password | Use jq for escaping |
| "manifest media type not supported" | Docker BuildKit issue | Use `--provenance=false` |
| "AccessDeniedException" | Missing IAM permissions | Check CloudMR Brain Lambda role |
| "State Machine not found" | Wrong account or region | Verify CloudFormation stack |
| "Computing unit already exists" | Duplicate registration | Delete and re-register or update |

### Debug Commands

```bash
# Test authentication
curl -X POST "$CLOUDMR_API_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$CLOUDMR_EMAIL\",\"password\":\"$CLOUDMR_PASSWORD\"}" | jq .

# List computing units
curl -H "Authorization: Bearer $ID_TOKEN" \
  "$CLOUDMR_API_URL/api/computing-unit/list?app_name=CAMRIE" | jq .

# Check step function
aws stepfunctions describe-state-machine \
  --state-machine-arn "$STATE_MACHINE_ARN" --region us-east-1

# Check stack outputs
aws cloudformation describe-stacks \
  --stack-name mroptimum-app --query 'Stacks[0].Outputs' --region us-east-1
```

---

## Next Steps

1. **Register your computing unit**: Run `register-computing-unit.sh`
2. **Test job submission**: Run `submit-job.sh` interactively
3. **Automate in CI/CD**: Add both scripts to your GitHub Actions workflow
4. **Monitor execution**: Use CloudMR Brain dashboard or AWS console
5. **Retrieve results**: Check S3 buckets for job outputs

---

## Reference

### API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/auth/login` | POST | Authenticate user |
| `/api/computing-unit/register` | POST | Register computing unit |
| `/api/computing-unit/list` | GET | List computing units |
| `/api/pipeline/queue_job` | POST | Queue job |

### CloudMRHub Account Details

- **Account ID**: 262361552878
- **Region**: us-east-1
- **Result Bucket**: cloudmr-results-cloudmrhub-brain-us-east-1
- **Failed Bucket**: cloudmr-failed-cloudmrhub-brain-us-east-1
- **Data Bucket**: cloudmr-data-cloudmrhub-brain-us-east-1

### Important Notes

- Mode 1 computing units run **in CloudMRHub's AWS account**
- Mode 2 computing units run **in your AWS account**
- Both modes use the same Step Function code
- Job selection priority: computing_unit_id → mode → auto-select
- Tokens expire after ~1 hour; re-login if needed

