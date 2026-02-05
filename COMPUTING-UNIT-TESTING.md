# Computing Unit Workflow - Testing Guide

## Pre-Testing Checklist

Before running the scripts, ensure:

- [ ] CloudMR Brain credentials available
- [ ] CloudMR Brain API URL known
- [ ] AWS credentials configured (for CloudFormation queries)
- [ ] CloudFormation stack deployed (mroptimum-app or custom name)
- [ ] `curl`, `jq`, `aws cli` installed
- [ ] Internet connectivity confirmed

---

## Test 1: Registration Script Validation

### Test 1.1: Help and Syntax

```bash
# Check script syntax
bash -n scripts/register-computing-unit.sh
# Expected: No output (success)

# Check script is executable
ls -lh scripts/register-computing-unit.sh
# Expected: -rwxrwxr-x ... register-computing-unit.sh
```

### Test 1.2: Missing Credentials

```bash
# Run without credentials
./scripts/register-computing-unit.sh
# Expected: Error message about CLOUDMR_API_URL not set
```

### Test 1.3: Invalid Credentials

```bash
export CLOUDMR_EMAIL="test@test.com"
export CLOUDMR_PASSWORD="wrongpassword"
export CLOUDMR_API_URL="https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"

./scripts/register-computing-unit.sh
# Expected: [ERROR] Login failed: {error message}
```

### Test 1.4: Mode 1 Registration (CloudMRHub)

```bash
# Prerequisites
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="your_password"
export CLOUDMR_API_URL="https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"
export AWS_PROFILE="your-aws-profile"

# Run registration
./scripts/register-computing-unit.sh

# Expected output:
# [SUCCESS] Logged in as: your@email.com
# [SUCCESS] State Machine ARN: arn:aws:states:us-east-1:262361552878:...
# [SUCCESS] Mode 1 (CloudMRHub Managed) - Provider: cloudmrhub
# [SUCCESS] Computing unit registered: {uuid}
# [INFO] Available computing units: [{...}]

# Verify in CloudMR Brain
curl -H "Authorization: Bearer $ID_TOKEN" \
  "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod/api/computing-unit/list?app_name=MR%20Optimum" \
  | jq '.units[] | {id: .computingUnitId, mode: .mode}'
# Expected: Computing unit with mode: "mode_1"
```

### Test 1.5: Mode 2 Registration (User-Owned)

```bash
# Register with Mode 2
export MODE="mode_2"
./scripts/register-computing-unit.sh

# Expected:
# [SUCCESS] Mode 2 (User Owned) - Provider: user - Account: 123456789012
# [SUCCESS] Computing unit registered: {uuid}

# Verify both units are registered
curl -H "Authorization: Bearer $ID_TOKEN" \
  "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod/api/computing-unit/list?app_name=MR%20Optimum" \
  | jq '.units[] | {mode: .mode, provider: .provider, account: .awsAccountId}'

# Expected output:
# {
#   "mode": "mode_1",
#   "provider": "cloudmrhub",
#   "account": "262361552878"
# }
# {
#   "mode": "mode_2",
#   "provider": "user",
#   "account": "YOUR_ACCOUNT"
# }
```

### Test 1.6: Custom State Machine ARN

```bash
# Get ARN manually
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
  --stack-name mroptimum-app \
  --query 'Stacks[0].Outputs[?OutputKey==`CalculationStateMachineArn`].OutputValue' \
  --output text)

echo "State Machine ARN: $STATE_MACHINE_ARN"

# Register with explicit ARN
export STATE_MACHINE_ARN="$STATE_MACHINE_ARN"
./scripts/register-computing-unit.sh

# Expected: Registration succeeds with provided ARN
```

---

## Test 2: Job Submission Script Validation

### Test 2.1: Help and Syntax

```bash
# Check script syntax
bash -n scripts/submit-job.sh
# Expected: No output (success)

# Check script is executable
ls -lh scripts/submit-job.sh
# Expected: -rwxrwxr-x ... submit-job.sh
```

### Test 2.2: Interactive Mode (Default)

```bash
# Prerequisites (from Test 1.4)
source ~/.cloudmr_env  # Or set manually

# Run interactively
./scripts/submit-job.sh

# Expected prompts:
# 1. CloudMR Email: [accepts your email or shows it]
# 2. CloudMR Password: [prompts if not set]
# 3. Available modes menu:
#    1) mode_1 (CloudMRHub Managed)
#    2) mode_2 (User Owned)
#    3) Select specific computing unit

# Select option 1 (mode_1)
# Expected output:
# [SUCCESS] Found 1 computing unit(s)
# [SUCCESS] Job queued successfully!
# [INFO] Execution ARN: arn:aws:states:us-east-1:262361552878:execution:...
```

### Test 2.3: Pattern 1 - Queue by Mode 1

```bash
source ~/.cloudmr_env

# Submit to Mode 1
export MODE="mode_1"
./scripts/submit-job.sh

# Verify execution
EXECUTION_ARN="arn:aws:states:us-east-1:262361552878:execution:..."
aws stepfunctions describe-execution --execution-arn "$EXECUTION_ARN"
# Expected: Status RUNNING or SUCCEEDED

# Expected response:
# [SUCCESS] Job queued successfully!
# [INFO] Execution ARN: arn:aws:states:us-east-1:262361552878:execution:...
```

### Test 2.4: Pattern 2 - Queue by Mode 2

```bash
source ~/.cloudmr_env

# Submit to Mode 2
export MODE="mode_2"
./scripts/submit-job.sh

# Expected output:
# [SUCCESS] Job queued successfully!
# [INFO] Execution ARN: arn:aws:states:us-east-1:YOUR_ACCOUNT:execution:...

# Verify execution (should be in your account)
aws stepfunctions describe-execution \
  --execution-arn "arn:aws:states:us-east-1:YOUR_ACCOUNT:execution:..." \
  --region us-east-1
```

### Test 2.5: Pattern 3 - Queue by Computing Unit ID

```bash
source ~/.cloudmr_env

# Get computing unit ID
COMPUTING_UNIT_ID=$(curl -s -H "Authorization: Bearer $ID_TOKEN" \
  "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod/api/computing-unit/list?app_name=MR%20Optimum" \
  | jq -r '.units[0].computingUnitId')

echo "Using computing unit: $COMPUTING_UNIT_ID"

# Submit with specific unit
export COMPUTING_UNIT_ID="$COMPUTING_UNIT_ID"
./scripts/submit-job.sh

# Expected:
# [SUCCESS] Job queued successfully!
# [INFO] Execution ARN: arn:aws:states:...
```

### Test 2.6: Non-Interactive Mode (CI/CD)

```bash
# Set all parameters
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="your_password"
export CLOUDMR_API_URL="https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"
export MODE="mode_1"
export INTERACTIVE="false"

# Run non-interactively
./scripts/submit-job.sh

# Expected: No prompts, direct execution
# [SUCCESS] Authentication successful
# [SUCCESS] Found X computing unit(s)
# [SUCCESS] Job queued successfully!
```

### Test 2.7: Custom Job Name

```bash
source ~/.cloudmr_env

# Submit with custom name
export PIPELINE_ALIAS="my-test-job-$(date +%s)"
export MODE="mode_1"
./scripts/submit-job.sh

# Expected: Job appears with custom name in CloudMR Brain
```

---

## Test 3: End-to-End Workflow

### Test 3.1: Complete Registration + Job Submission

```bash
#!/bin/bash
set -e

# Setup
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="your_password"
export CLOUDMR_API_URL="https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"

echo "=== Step 1: Register Mode 1 ==="
export MODE="mode_1"
./scripts/register-computing-unit.sh

echo ""
echo "=== Step 2: Register Mode 2 ==="
export MODE="mode_2"
./scripts/register-computing-unit.sh

echo ""
echo "=== Step 3: Submit Job (Mode 1) ==="
export MODE="mode_1"
export INTERACTIVE="false"
./scripts/submit-job.sh

echo ""
echo "=== Step 4: Submit Job (Mode 2) ==="
export MODE="mode_2"
./scripts/submit-job.sh

echo ""
echo "=== Success ==="
```

### Test 3.2: Verify CloudMR Brain

```bash
# List all computing units
curl -H "Authorization: Bearer $ID_TOKEN" \
  "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod/api/computing-unit/list?app_name=MR%20Optimum" \
  | jq '.units | length'

# Expected: 2 (mode_1 and mode_2)

# List recent jobs
curl -H "Authorization: Bearer $ID_TOKEN" \
  "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod/api/pipeline/list?limit=10" \
  | jq '.pipelines[] | {alias: .alias, status: .status}'

# Expected: Recently submitted jobs shown
```

---

## Test 4: Error Scenarios

### Test 4.1: Network Error

```bash
# Use invalid API URL
export CLOUDMR_API_URL="https://invalid.endpoint.com"
./scripts/register-computing-unit.sh

# Expected: Network error with clear message
# [ERROR] Could not connect to API (network error)
```

### Test 4.2: Missing Stack

```bash
# Use non-existent stack
export STACK_NAME="nonexistent-stack"
./scripts/register-computing-unit.sh

# Expected: Clear error about missing stack
# [ERROR] Could not find CalculationStateMachineArn in stack outputs
```

### Test 4.3: No Computing Units

```bash
# Create new email/app in CloudMR (one without computing units)
export APP_NAME="UnregisteredApp"
./scripts/submit-job.sh

# Expected:
# [ERROR] No computing units found for app: UnregisteredApp
# Try registering first: ./scripts/register-computing-unit.sh
```

### Test 4.4: Special Characters in Password

```bash
# Set password with special characters
export CLOUDMR_PASSWORD='p@ssw0rd!#$%&*(){}[]'
./scripts/register-computing-unit.sh

# Expected: Should handle special characters correctly
# [SUCCESS] Logged in successfully
```

---

## Test 5: Performance & Timing

### Test 5.1: Registration Speed

```bash
time ./scripts/register-computing-unit.sh

# Expected: 3-5 seconds total
# real	0m4.123s
# user	0m0.456s
# sys	0m0.234s
```

### Test 5.2: Job Submission Speed

```bash
export MODE="mode_1"
time ./scripts/submit-job.sh

# Expected: 1-2 seconds total
# real	0m1.523s
# user	0m0.234s
# sys	0m0.123s
```

---

## Test 6: CloudMR Brain Integration

### Test 6.1: Verify Registration in Dashboard

```
1. Log into CloudMR Brain dashboard
2. Navigate to Settings → Apps → MR Optimum
3. Look for "Computing Units" section
4. Should see:
   - Mode 1 entry (provider: cloudmrhub, account: 262361552878)
   - Mode 2 entry (provider: user, account: YOUR_ACCOUNT)
```

### Test 6.2: Verify Jobs in Dashboard

```
1. Log into CloudMR Brain dashboard
2. Navigate to Jobs/Pipelines
3. Look for recently submitted jobs
4. Should see:
   - Job alias (from PIPELINE_ALIAS)
   - Status (QUEUED, RUNNING, or SUCCEEDED)
   - Computing unit used
   - Timestamps
```

### Test 6.3: Monitor Job Execution

```bash
# Get execution ARN from job submission
EXECUTION_ARN="arn:aws:states:us-east-1:262361552878:execution:..."

# Check status
aws stepfunctions describe-execution --execution-arn "$EXECUTION_ARN" \
  --query 'status'

# Expected: RUNNING → SUCCEEDED (or FAILED if error)

# Check logs
aws logs tail /aws/lambda/cloudmr-queuejob --follow

# Expected: Logs show job processing
```

---

## Test 7: Cleanup & Reset

### Test 7.1: Delete Computing Units (if needed)

```bash
# Note: Currently no delete API, but you can register new ones
# To test multiple registrations:

export APP_NAME="MR Optimum - Test"
./scripts/register-computing-unit.sh

# Lists independently registered units
curl -H "Authorization: Bearer $ID_TOKEN" \
  "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod/api/computing-unit/list?app_name=MR%20Optimum%20-%20Test" \
  | jq '.units | length'
```

---

## Test Results Template

```
Test Date: YYYY-MM-DD
Tester: Your Name
Environment: Local / CI-CD / Production

Test 1: Registration Script
├─ [ ] Syntax validation: PASS / FAIL
├─ [ ] Missing credentials handling: PASS / FAIL
├─ [ ] Invalid credentials handling: PASS / FAIL
├─ [ ] Mode 1 registration: PASS / FAIL
├─ [ ] Mode 2 registration: PASS / FAIL
├─ [ ] Custom State Machine ARN: PASS / FAIL
└─ [ ] Notes: ___________

Test 2: Job Submission Script
├─ [ ] Syntax validation: PASS / FAIL
├─ [ ] Interactive mode: PASS / FAIL
├─ [ ] Pattern 1 (mode_1): PASS / FAIL
├─ [ ] Pattern 2 (mode_2): PASS / FAIL
├─ [ ] Pattern 3 (unit ID): PASS / FAIL
├─ [ ] Non-interactive mode: PASS / FAIL
└─ [ ] Notes: ___________

Test 3: End-to-End
├─ [ ] Register + Submit: PASS / FAIL
├─ [ ] CloudMR Brain verification: PASS / FAIL
├─ [ ] Job execution: PASS / FAIL
└─ [ ] Notes: ___________

Test 4: Error Handling
├─ [ ] Network errors: PASS / FAIL
├─ [ ] Missing resources: PASS / FAIL
├─ [ ] Special characters: PASS / FAIL
└─ [ ] Notes: ___________

Overall Result: PASS / FAIL
Issues Found: ___________
Recommendations: ___________
```

---

## Troubleshooting During Tests

### Common Issues & Solutions

#### "jq: command not found"
```bash
# Install jq
brew install jq          # macOS
apt-get install jq       # Ubuntu/Debian
yum install jq           # CentOS/RHEL
```

#### "curl: (7) Failed to connect"
```bash
# Check internet connectivity
ping google.com

# Verify API URL
echo $CLOUDMR_API_URL

# Test with curl
curl -v "$CLOUDMR_API_URL/api/auth/login"
```

#### "aws: command not found"
```bash
# Install AWS CLI
brew install awscli      # macOS
pip install awscliv2     # Python/pip

# Configure credentials
aws configure
```

#### "CalculationStateMachineArn not found"
```bash
# Verify stack exists
aws cloudformation list-stacks --query 'StackSummaries[?StackName==`mroptimum-app`]'

# Check outputs
aws cloudformation describe-stacks --stack-name mroptimum-app --query 'Stacks[0].Outputs'

# Use custom ARN
export STATE_MACHINE_ARN="arn:aws:states:..."
```

---

## Next Steps After Testing

1. **All tests pass** → Scripts ready for production
2. **Some tests fail** → Check logs and error messages
3. **Integration issues** → Contact CloudMR Brain support
4. **Performance issues** → Check network connectivity
5. **Ready to deploy** → Add to CI/CD pipelines

---

## Quick Test Commands

```bash
# Quick 5-minute test
source ~/.cloudmr_env
./scripts/register-computing-unit.sh && \
export MODE="mode_1" && \
./scripts/submit-job.sh && \
echo "✓ All tests passed!"

# Detailed test suite
bash -n scripts/register-computing-unit.sh && \
bash -n scripts/submit-job.sh && \
./scripts/register-computing-unit.sh && \
./scripts/submit-job.sh && \
echo "✓ Complete test suite passed!"
```

