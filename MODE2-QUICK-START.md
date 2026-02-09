# Mode 2 Deployment - Quick Summary

## What is Mode 2?

Mode 2 deploys MR Optimum compute infrastructure in **YOUR AWS account**. You pay for compute, data stays in your S3.

---

## Quick Start (2 Steps)

### Step 1: Deploy the Stack

```bash
cd mode2-deployment/
./deploy-mode2.sh
```

**What it does:**
- Creates S3 buckets (data, results, failed) in YOUR account
- Deploys ECS cluster + Fargate tasks
- Creates Lambda functions
- Sets up Step Function state machine
- **Auto-registers** computing unit with CloudMR Brain

### Step 2: Verify (Optional)

```bash
# Check if auto-registration worked
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="yourpassword"
export CLOUDMR_API_URL="https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"

./scripts/register-mode2.sh
```

---

## Manual Registration (if needed)

If auto-registration fails, run:

```bash
export CLOUDMR_EMAIL="your@email.com"
export CLOUDMR_PASSWORD="yourpassword"
export CLOUDMR_API_URL="https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"
export STACK_NAME="mroptimum-mode2"

./scripts/register-mode2.sh
```

---

## Verify Computing Units

```bash
# Login
ID_TOKEN=$(curl -s -X POST "$CLOUDMR_API_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$CLOUDMR_EMAIL\",\"password\":\"$CLOUDMR_PASSWORD\"}" | jq -r '.id_token')

# List computing units
curl -s -H "Authorization: Bearer $ID_TOKEN" \
  "$CLOUDMR_API_URL/api/computing-unit/list?app_name=MR%20Optimum" | jq .
```

You should see:
- **Mode 1** - `mode: "mode_1"`, `provider: "cloudmrhub"` (CloudMRHub managed)
- **Mode 2** - `mode: "mode_2"`, `provider: "user"` (Your account) ← NEW!

---

## Cost Estimate

Example job (4 vCPU, 8GB RAM, 10 minutes):
- **~$0.03 - $0.05 per job**
- Charged to YOUR AWS account

---

## Cleanup

```bash
aws cloudformation delete-stack --stack-name mroptimum-mode2 --region us-east-1
```

---

## Troubleshooting

### Stack deployment fails
```bash
aws cloudformation describe-stack-events \
    --stack-name mroptimum-mode2 \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

### Registration fails
```bash
# Check stack outputs
aws cloudformation describe-stacks \
    --stack-name mroptimum-mode2 \
    --query 'Stacks[0].Outputs'

# Verify State Machine ARN exists
```

### Jobs not routing to Mode 2
- Check CloudMR Brain UI shows Mode 2 option
- Verify computing unit is registered with correct `mode_2`

---

## Files Reference

| File | Purpose |
|------|---------|
| `MODE2-DEPLOYMENT-GUIDE.md` | Comprehensive guide (architecture, costs, troubleshooting) |
| `mode2-deployment/deploy-mode2.sh` | Deploy CloudFormation stack |
| `mode2-deployment/template-mode2.yaml` | CloudFormation template |
| `scripts/register-mode2.sh` | Register computing unit |
| `scripts/mode2-quick-reference.sh` | Shell functions for common tasks |

---

## Architecture

```
User → CloudMR Brain → Mode 2 Computing Unit (YOUR AWS)
                           ↓
                    Step Function (YOUR account)
                           ↓
                    Lambda/Fargate (YOUR compute)
                           ↓
                    S3 Buckets (YOUR storage)
                           ↓
                    Callback → CloudMR Brain
```

---

## Key Differences: Mode 1 vs Mode 2

| Feature | Mode 1 | Mode 2 |
|---------|--------|--------|
| Infrastructure | CloudMRHub account | YOUR account |
| Costs | CloudMRHub pays | YOU pay |
| Data location | CloudMRHub S3 | Your S3 |
| Control | Shared | Dedicated |

---

For detailed documentation, see `MODE2-DEPLOYMENT-GUIDE.md`
