# Computing Unit Workflow - Visual Summary

## Task 1: Registration Workflow (`register-computing-unit.sh`)

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                  Registration Workflow                           │
└─────────────────────────────────────────────────────────────────┘

  ┌──────────────────────────────────────────────────────────┐
  │ Step 1: Validate Inputs                                  │
  │ - Check tools (curl, jq, aws)                            │
  │ - Verify credentials provided                            │
  └───────────────┬──────────────────────────────────────────┘
                  │
  ┌───────────────▼──────────────────────────────────────────┐
  │ Step 2: Login to CloudMR Brain                           │
  │ - POST /api/auth/login                                   │
  │ - Get ID_TOKEN, USER_ID                                  │
  │ - Handle authentication errors                           │
  └───────────────┬──────────────────────────────────────────┘
                  │
  ┌───────────────▼──────────────────────────────────────────┐
  │ Step 3: Get State Machine ARN                            │
  │ - Option A: Use provided STATE_MACHINE_ARN               │
  │ - Option B: Auto-detect from CloudFormation              │
  │   • Get stack outputs                                    │
  │   • Look for CalculationStateMachineArn                  │
  └───────────────┬──────────────────────────────────────────┘
                  │
  ┌───────────────▼──────────────────────────────────────────┐
  │ Step 4: Determine Provider                               │
  │ - Check AWS account ID                                   │
  │ - If 262361552878 → Mode 1 (provider: cloudmrhub)        │
  │ - Else → Mode 2 (provider: user)                         │
  └───────────────┬──────────────────────────────────────────┘
                  │
  ┌───────────────▼──────────────────────────────────────────┐
  │ Step 5: Register Computing Unit                          │
  │ - POST /api/computing-unit/register                      │
  │ - Pass: appName, mode, provider, ARN, buckets            │
  │ - Get back: computingUnitId                              │
  └───────────────┬──────────────────────────────────────────┘
                  │
  ┌───────────────▼──────────────────────────────────────────┐
  │ Step 6: List & Verify                                    │
  │ - GET /api/computing-unit/list                           │
  │ - Show all registered units for app                      │
  │ - Confirm registration successful                        │
  └─────────────────────────────────────────────────────────┘
```

### Key Decisions Made

```
Which Mode?
├─ If AWS account = 262361552878 → Mode 1 (provider: cloudmrhub)
└─ If AWS account = your account → Mode 2 (provider: user)

State Machine ARN?
├─ If STATE_MACHINE_ARN env var set → Use it
└─ Else → Auto-detect from CloudFormation stack

Provider Value?
├─ Mode 1 → provider: "cloudmrhub"
└─ Mode 2 → provider: "user"
```

### Usage Patterns

```
1. Basic (auto-detect everything)
   $ ./scripts/register-computing-unit.sh

2. Mode 2 (user-owned)
   $ export MODE="mode_2"
   $ ./scripts/register-computing-unit.sh

3. Custom stack name
   $ export STACK_NAME="my-stack"
   $ ./scripts/register-computing-unit.sh

4. Manual State Machine ARN
   $ export STATE_MACHINE_ARN="arn:aws:..."
   $ ./scripts/register-computing-unit.sh
```

---

## Task 2: Job Submission Workflow (`submit-job.sh`)

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│              Job Submission Workflow                             │
└─────────────────────────────────────────────────────────────────┘

  ┌──────────────────────────────────────────────────────────┐
  │ Step 1: Validate Inputs                                  │
  │ - Check tools (curl, jq)                                 │
  │ - Prompt for credentials if missing                      │
  └───────────────┬──────────────────────────────────────────┘
                  │
  ┌───────────────▼──────────────────────────────────────────┐
  │ Step 2: Authenticate                                     │
  │ - POST /api/auth/login                                   │
  │ - Store ID_TOKEN for future calls                        │
  └───────────────┬──────────────────────────────────────────┘
                  │
  ┌───────────────▼──────────────────────────────────────────┐
  │ Step 3: Query Available Units                            │
  │ - GET /api/computing-unit/list?app_name=APP              │
  │ - Show mode, provider, account for each                  │
  └───────────────┬──────────────────────────────────────────┘
                  │
  ┌───────────────▼──────────────────────────────────────────┐
  │ Step 4: Select Computing Unit                            │
  │ - Priority 1: Explicit COMPUTING_UNIT_ID                 │
  │ - Priority 2: MODE env var                               │
  │ - Priority 3: Interactive menu (if INTERACTIVE=true)     │
  │ - Priority 4: Default to mode_1                          │
  └───────────────┬──────────────────────────────────────────┘
                  │
  ┌───────────────▼──────────────────────────────────────────┐
  │ Step 5: Prepare Task Definition                          │
  │ - Use TASK_DEFINITION env var or default                 │
  │ - Generate PIPELINE_ALIAS if not provided                │
  └───────────────┬──────────────────────────────────────────┘
                  │
  ┌───────────────▼──────────────────────────────────────────┐
  │ Step 6: Queue Job                                        │
  │ - POST /api/pipeline/queue_job                           │
  │ - Send payload with job details                          │
  │ - Get back: executionArn, pipelineId, computingUnit      │
  └───────────────┬──────────────────────────────────────────┘
                  │
  ┌───────────────▼──────────────────────────────────────────┐
  │ Step 7: Display Results                                  │
  │ - Show execution ARN                                     │
  │ - Show pipeline UUID                                     │
  │ - Show computing unit used                               │
  │ - Provide next steps                                     │
  └─────────────────────────────────────────────────────────┘
```

### Three Queueing Patterns

```
Pattern 1: Queue by Mode 1 (CloudMRHub Managed)
────────────────────────────────────────────────
{
  "cloudapp_name": "CAMRIE",
  "alias": "my-job-123",
  "mode": "mode_1",        ◄── Select by mode
  "task": {
    "task_type": "brain_calculation"
  }
}

Response:
{
  "executionArn": "arn:aws:states:us-east-1:262361552878:execution:...",
  "pipelineId": "abc-123",
  "computingUnit": {
    "computingUnitId": "550e8400-...",
    "mode": "mode_1"
  }
}
```

```
Pattern 2: Queue by Mode 2 (User-Owned)
────────────────────────────────────────
{
  "cloudapp_name": "CAMRIE",
  "alias": "my-job-456",
  "mode": "mode_2",        ◄── Select by mode
  "task": {
    "task_type": "brain_calculation"
  }
}

Response:
{
  "executionArn": "arn:aws:states:us-east-1:YOUR_ACCOUNT:execution:...",
  "pipelineId": "xyz-789",
  "computingUnit": {
    "computingUnitId": "661f9511-...",
    "mode": "mode_2"
  }
}
```

```
Pattern 3: Queue by Computing Unit ID
──────────────────────────────────────
{
  "cloudapp_name": "CAMRIE",
  "alias": "my-job-789",
  "computing_unit_id": "550e8400-e29b-41d4-a716-446655440000",  ◄── Select by ID
  "task": {
    "task_type": "brain_calculation"
  }
}

Response: Same as Pattern 1 or 2 (depending on selected unit)
```

### Usage Patterns

```
1. Interactive (prompts for selection)
   $ ./scripts/submit-job.sh

2. Select Mode 1
   $ export MODE="mode_1"
   $ ./scripts/submit-job.sh

3. Select Mode 2
   $ export MODE="mode_2"
   $ ./scripts/submit-job.sh

4. Select specific computing unit
   $ export COMPUTING_UNIT_ID="550e8400-..."
   $ ./scripts/submit-job.sh

5. Non-interactive (for CI/CD)
   $ export MODE="mode_1"
   $ export INTERACTIVE="false"
   $ ./scripts/submit-job.sh

6. Custom job name
   $ export PIPELINE_ALIAS="my-special-job"
   $ ./scripts/submit-job.sh
```

---

## Computing Unit Selection Priority

```
User provides COMPUTING_UNIT_ID?
│
├─ YES → Use that specific unit ✓ (Priority 1)
│
└─ NO → User provides MODE?
       │
       ├─ YES → Queue with that mode ✓ (Priority 2)
       │
       └─ NO → INTERACTIVE=true?
              │
              ├─ YES → Show menu, ask user ✓ (Priority 3)
              │
              └─ NO → Default to mode_1 ✓ (Priority 4)
```

---

## Payload Structure Comparison

### Registration Payload (Mode 1)

```json
{
  "appName": "MR Optimum",
  "mode": "mode_1",
  "provider": "cloudmrhub",          ← CloudMRHub account
  "awsAccountId": "262361552878",
  "region": "us-east-1",
  "stateMachineArn": "arn:aws:states:us-east-1:262361552878:stateMachine:...",
  "resultsBucket": "cloudmr-results-cloudmrhub-brain-us-east-1",
  "failedBucket": "cloudmr-failed-cloudmrhub-brain-us-east-1",
  "dataBucket": "cloudmr-data-cloudmrhub-brain-us-east-1",
  "isDefault": true
}
```

### Registration Payload (Mode 2)

```json
{
  "appName": "MR Optimum",
  "mode": "mode_2",
  "provider": "user",                ← User account
  "awsAccountId": "123456789012",    ← Different account
  "region": "us-east-1",
  "stateMachineArn": "arn:aws:states:us-east-1:123456789012:stateMachine:...",
  "resultsBucket": "my-results-bucket",
  "failedBucket": "my-failed-bucket",
  "dataBucket": "my-data-bucket",
  "isDefault": false
}
```

### Job Queueing Payload (Mode-based)

```json
{
  "cloudapp_name": "CAMRIE",
  "alias": "mr-opt-job-1707142020",
  "mode": "mode_1",                 ← CloudMR Brain auto-selects unit
  "task": {
    "task_type": "brain_calculation",
    "parameters": {
      "input_format": "nifti",
      "output_format": "nifti"
    }
  }
}
```

### Job Queueing Payload (Unit-based)

```json
{
  "cloudapp_name": "CAMRIE",
  "alias": "mr-opt-job-1707142020",
  "computing_unit_id": "550e8400-e29b-41d4-a716-446655440000",  ← Explicit unit
  "task": {
    "task_type": "brain_calculation",
    "parameters": {
      "input_format": "nifti",
      "output_format": "nifti"
    }
  }
}
```

---

## Environment Variable Reference

### Registration Script

```
┌─ CLOUDMR_EMAIL          Required  CloudMR user email
├─ CLOUDMR_PASSWORD       Required  CloudMR user password
├─ CLOUDMR_API_URL        Required  CloudMR Brain API endpoint
├─ APP_NAME               Optional  CloudApp name (default: MR Optimum)
├─ MODE                   Optional  mode_1 or mode_2 (default: mode_1)
├─ AWS_ACCOUNT_ID         Optional  AWS account (auto-detected)
├─ STATE_MACHINE_ARN      Optional  Step Function ARN (auto-detected)
├─ STACK_NAME             Optional  CloudFormation stack (default: mroptimum-app)
└─ REGION                 Optional  AWS region (default: us-east-1)
```

### Job Submission Script

```
┌─ CLOUDMR_EMAIL          Required  CloudMR user email
├─ CLOUDMR_PASSWORD       Required  CloudMR user password
├─ CLOUDMR_API_URL        Required  CloudMR Brain API endpoint
├─ APP_NAME               Optional  CloudApp name (default: CAMRIE)
├─ MODE                   Optional  mode_1 or mode_2 (selection)
├─ COMPUTING_UNIT_ID      Optional  Specific unit UUID (selection)
├─ PIPELINE_ALIAS         Optional  Job name (auto-generated)
├─ TASK_DEFINITION        Optional  Job task (default: brain_calc)
└─ INTERACTIVE            Optional  Enable prompts (default: true)
```

---

## Error Handling

### Registration Script Errors

```
[ERROR] curl not installed
├─ Solution: Install curl

[ERROR] Login failed: Invalid credentials
├─ Solution: Check CLOUDMR_EMAIL and CLOUDMR_PASSWORD

[ERROR] Could not find CalculationStateMachineArn in stack outputs
├─ Solution: 
│  - Verify stack exists: aws cloudformation describe-stacks
│  - Provide STATE_MACHINE_ARN manually

[ERROR] Registration failed
├─ Solution: Check response above for details
└─ Check IAM permissions for CloudMR Brain API
```

### Job Submission Script Errors

```
[ERROR] No computing units found for app
├─ Solution: Run register-computing-unit.sh first

[ERROR] Job queueing failed
├─ Solution:
│  - Check CloudMR Brain Lambda IAM permissions
│  - Verify State Machine exists and is accessible
│  - Check S3 bucket access

[ERROR] Timeout or network error
├─ Solution: Check internet connection and API endpoint
```

---

## Quick Reference Table

| Task | Command | Time |
|------|---------|------|
| Register (Mode 1) | `./scripts/register-computing-unit.sh` | 3-5s |
| Register (Mode 2) | `MODE=mode_2 ./scripts/register-computing-unit.sh` | 3-5s |
| Submit (Interactive) | `./scripts/submit-job.sh` | 1-2s |
| Submit (Mode 1) | `MODE=mode_1 ./scripts/submit-job.sh` | 1-2s |
| Submit (By Unit ID) | `COMPUTING_UNIT_ID=uuid ./scripts/submit-job.sh` | 1-2s |

---

## Architecture Overview

```
┌───────────────────────────────────────────────────────────────┐
│                    CloudMR Brain                               │
│  (API Gateway + Lambda + DynamoDB)                             │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────▼────────────────┐
        │  POST /api/auth/login       │
        └──────────────────────────────┘
        ┌────────────▼────────────────┐
        │  POST /computing-unit/register
        └──────────────────────────────┘
        ┌────────────▼────────────────┐
        │  GET /computing-unit/list    │
        └──────────────────────────────┘
        ┌────────────▼────────────────┐
        │  POST /pipeline/queue_job    │
        └────────┬────────────────────┘
                 │
    ┌────────────▼──────────────┐
    │  Mode 1: CloudMRHub       │
    │  Account: 262361552878    │
    │  - Lambda                 │
    │  - Fargate                │
    │  - Step Function          │
    │  - S3 (shared)            │
    └───────────────────────────┘
    
    ┌────────────▼──────────────┐
    │  Mode 2: User-Owned       │
    │  Account: YOUR_ACCOUNT    │
    │  - Lambda                 │
    │  - Fargate                │
    │  - Step Function          │
    │  - S3 (your buckets)      │
    └───────────────────────────┘
```

---

## Summary

✅ **Task 1**: Registration workflow implemented with full Mode 1/2 support  
✅ **Task 2**: Job submission with three queueing patterns  
✅ **Documentation**: Complete guides + quick reference  
✅ **Error Handling**: Clear messages and solutions  
✅ **Ready for Use**: Both scripts tested and syntax-verified

