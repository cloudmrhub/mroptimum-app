# Queue Job Guide for MR Optimum

This guide explains how to use the queue job scripts to submit computation jobs to MR Optimum through CloudMR Brain.

## Prerequisites

1. **CloudMR Brain Account**: You need valid credentials for CloudMR Brain
2. **Tools**: `bash`, `curl`, `jq`
3. **Network**: Access to the CloudMR Brain API endpoint

## Setup

### 1. Configure Credentials

Create or update `exports_user.sh` with your CloudMR Brain credentials:

```bash
export CLOUDMR_EMAIL="your-email@example.com"
export CLOUDMR_PASSWORD="your-password"
```

> **Note**: Special characters in passwords (like `&`, `$`, etc.) are handled automatically by jq.

### 2. Source the File

Before running scripts, source the credentials file:

```bash
source exports_user.sh
```

## Quick Start

### Simple Job Queue (Recommended)

The simplest way to queue a job:

```bash
source exports_user.sh
./scripts/queue-job.sh
```

This script will:
1. ✅ Login to CloudMR Brain and get authentication token
2. ✅ Find the MR Optimum CloudApp
3. ✅ Queue the job for execution
4. ✅ Display execution details (including AWS Step Function ARN)

### Output Example

```
==========================================
  CloudMR Brain - Queue Job
==========================================
  API: https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod
==========================================

[INFO] Step 1: Logging in to CloudMR Brain...
[SUCCESS] Logged in as: u@user.com (user_id: cb5c1021-...)
[INFO] Step 2: Finding CloudApp 'MR Optimum'...
[SUCCESS] Found CloudApp ID: d8cecb2c-...
[INFO] Step 3: Queueing job (pipeline will be created automatically)...

[INFO] Job payload:
{
  "cloudapp_name": "MR Optimum",
  "alias": "Job-20260205-105432",
  "task": {
    "type": "snr_calculation",
    "parameters": {
      "test_mode": true,
      "timestamp": "2026-02-05T10:54:32-05:00",
      "echo": "Hello from queue-job.sh"
    }
  }
}

[INFO] Queue response:
{
  "executionArn": "arn:aws:states:us-east-1:469266894233:execution:...",
  ...
}

[SUCCESS] Job queued successfully!

==========================================
  Execution Details
==========================================
  Execution ARN: arn:aws:states:us-east-1:469266894233:execution:...
  Pipeline ID:   6f4fac1d-c28a-44c8-8768-24c8e8fca782
  CloudApp:      MR Optimum

  Monitor at AWS Console:
  https://us-east-1.console.aws.amazon.com/states/home?region=us-east-1#/executions/details/arn:aws:states:...
==========================================
```

## Advanced Usage

### Environment Variables

You can customize the job submission using environment variables:

```bash
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="password"
export CLOUDMR_API_URL="https://your-api-endpoint/Prod"  # Optional
export CLOUDAPP_NAME="MR Optimum"  # Optional, defaults to "MR Optimum"

./scripts/queue-job.sh
```

### Reusing Tokens

After running the script, it exports tokens to the environment. You can reuse them in the same session:

```bash
source exports_user.sh
./scripts/queue-job.sh

# Tokens are now available:
echo $ID_TOKEN
echo $USER_ID
echo $CLOUDAPP_ID
echo $PIPELINE_ID
echo $EXECUTION_ARN
```

### Custom Job Payloads

To modify the job parameters, edit the `queue_job()` function in `queue-job.sh`:

```bash
# Find this section in queue_job():
task_payload=$(jq -n \
    --arg cloudapp_name "$CLOUDAPP_NAME" \
    --arg alias "$job_alias" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        cloudapp_name: $cloudapp_name,
        alias: $alias,
        task: {
            type: "snr_calculation",  # Change task type
            parameters: {
                test_mode: true,
                timestamp: $timestamp,
                # Add your custom parameters here
                custom_param: "value"
            }
        }
    }')
```

## Script Files

### `scripts/queue-job.sh`

**Purpose**: Main script for queueing jobs  
**Status**: ✅ Production-ready  
**Features**:
- Login to CloudMR Brain
- Find CloudApp by name
- Queue job with automatic pipeline creation
- Display execution details
- Export tokens for reuse

**Usage**:
```bash
source exports_user.sh
./scripts/queue-job.sh
```

### `scripts/test-queue-job.sh`

**Purpose**: Interactive menu for testing various operations  
**Status**: ✅ Available for testing  
**Features**:
- Login (option 1)
- Get user profile (option 2)
- List CloudApps (option 3)
- List computing units (option 4)
- List user data (option 5)
- List pipelines (option 6)
- Create pipeline request (option 8)
- Queue job (option 9)
- Full test sequence (option 10)

**Usage**:
```bash
source exports_user.sh
./scripts/test-queue-job.sh --menu
```

Or run specific actions:
```bash
./scripts/test-queue-job.sh --full      # Run full test
./scripts/test-queue-job.sh --list-apps # List CloudApps
```

### `scripts/quick-queue-test.sh`

**Purpose**: Minimal one-shot job submission  
**Status**: ✅ Available  
**Features**:
- Fast job queueing without interactive menu
- Step-by-step progress output
- Execution ARN display

**Usage**:
```bash
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="password"
./scripts/quick-queue-test.sh
```

## Troubleshooting

### Login Fails: "Invalid username or password"

**Cause**: Credentials are incorrect or account doesn't exist  
**Solution**:
1. Verify email and password are correct
2. Check that the account is registered and verified in CloudMR Brain
3. Ensure special characters in password are not being escaped incorrectly

### CloudApp Not Found

**Cause**: The CloudApp name doesn't match exactly  
**Solution**:
1. Run the script to see available CloudApps:
   ```bash
   source exports_user.sh
   ./scripts/test-queue-job.sh --list-apps
   ```
2. Update `CLOUDAPP_NAME` variable if needed:
   ```bash
   export CLOUDAPP_NAME="Your CloudApp Name"
   ./scripts/queue-job.sh
   ```

### Job Queue Error: "Parameter alias is required"

**Cause**: The API endpoint format changed or requires different parameters  
**Solution**: This typically means you're calling the wrong endpoint. The script should automatically use the correct `/api/pipeline/queue_job` endpoint.

### Job Queue Error: "AccessDeniedException"

**Cause**: The CloudMR Brain infrastructure doesn't have permission to invoke Step Functions  
**Solution**: This is an infrastructure issue in CloudMR Brain. Contact the CloudMRHub team to:
1. Update the QueueJobFunction Lambda execution role
2. Add permission to invoke the MR Optimum Step Function
3. Redeploy the CloudMR Brain infrastructure

### curl or jq Command Not Found

**Cause**: Required tools are not installed  
**Solution**:
- Ubuntu/Debian: `sudo apt-get install curl jq`
- macOS: `brew install curl jq`
- CentOS/RHEL: `sudo yum install curl jq`

## Architecture

The job queueing flow:

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Your Local Machine                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  queue-job.sh                                                │   │
│  │  ├─ Login → CloudMR Brain                                   │   │
│  │  ├─ Find CloudApp → Get CloudApp ID                         │   │
│  │  └─ Queue Job → Send to CloudMR Brain API                   │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
                              ↓ HTTP/REST
┌──────────────────────────────────────────────────────────────────────┐
│                      CloudMR Brain (AWS)                             │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  API Gateway + Lambda (QueueJobFunction)                    │   │
│  │  ├─ Validate credentials                                    │   │
│  │  ├─ Create pipeline record in DynamoDB                      │   │
│  │  └─ Start Step Function execution                           │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────────┐
│                  MR Optimum (Your AWS Account)                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Step Function (JobChooserStateMachine)                      │   │
│  │  ├─ Choice: Small job? → Lambda                             │   │
│  │  └─ Choice: Large job? → Fargate                            │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

## Next Steps

1. **Monitor Execution**: Click the AWS Console link in the output to watch the job run
2. **Check Results**: Results will be stored in S3 buckets after execution
3. **Custom Calculations**: Modify the task type and parameters to run different calculations
4. **Batch Jobs**: Create a loop to submit multiple jobs:
   ```bash
   for i in {1..10}; do
     CLOUDAPP_NAME="MR Optimum" ./scripts/queue-job.sh
     sleep 2
   done
   ```

## Support

For issues with:
- **Script errors**: Check troubleshooting section above
- **CloudMR Brain API**: Contact CloudMRHub team
- **MR Optimum infrastructure**: Check `/data/PROJECTS/mroptimum-app/.github/instructions/`
