#!/bin/bash
# Quick Reference - Job Queueing with MR Optimum
# =============================================================================

# Setup (one time)
cd /data/PROJECTS/mroptimum-app

# Run the job queueing script
source exports_user.sh
./scripts/queue-job.sh

# That's it! The script will:
# 1. Login to CloudMR Brain
# 2. Find the MR Optimum CloudApp
# 3. Queue your job
# 4. Show execution details

# =============================================================================
# Options
# =============================================================================

# Option 1: Interactive menu with more options
source exports_user.sh
./scripts/test-queue-job.sh --menu

# Option 2: Full test sequence
source exports_user.sh
./scripts/test-queue-job.sh --full

# Option 3: List available CloudApps
source exports_user.sh
./scripts/test-queue-job.sh --list-apps

# Option 4: One-shot with inline credentials
CLOUDMR_EMAIL="u@user.com" CLOUDMR_PASSWORD='tYeY4Huw06F3H5&X' ./scripts/quick-queue-test.sh

# =============================================================================
# Environment Variables You Can Set
# =============================================================================

export CLOUDMR_EMAIL="your-email@example.com"       # Your CloudMR Brain email
export CLOUDMR_PASSWORD="your-password"             # Your CloudMR Brain password  
export CLOUDMR_API_URL="https://api.url/Prod"       # Optional: override API endpoint
export CLOUDAPP_NAME="MR Optimum"                   # Optional: override CloudApp name

# =============================================================================
# After Running (tokens are exported)
# =============================================================================

# These variables are available in your shell session:
echo $ID_TOKEN              # Your authentication token
echo $USER_ID               # Your user ID
echo $CLOUDAPP_ID           # The MR Optimum CloudApp ID
echo $PIPELINE_ID           # The created pipeline ID
echo $EXECUTION_ARN         # The Step Function execution ARN

# =============================================================================
# Monitoring
# =============================================================================

# Click the AWS Console link from the output, or:
# https://us-east-1.console.aws.amazon.com/states/home?region=us-east-1#/executions

# Or check locally:
echo "Pipeline: $PIPELINE_ID"
echo "Execution: $EXECUTION_ARN"

# =============================================================================
# Troubleshooting
# =============================================================================

# Login failed?
# → Check exports_user.sh has correct email and password
# → Special characters in password should work (handled by jq)

# CloudApp not found?
# → Run: source exports_user.sh && ./scripts/test-queue-job.sh --list-apps
# → Check CLOUDAPP_NAME matches exactly

# Job not executing?
# → Likely AWS IAM permission issue (infrastructure-side fix needed)
# → Job queueing API call succeeds but Step Function invocation fails

# =============================================================================
# Full Documentation
# =============================================================================

# See: QUEUE_JOB_GUIDE.md
# See: JOB_QUEUEING_TEST_SUMMARY.md

# =============================================================================
