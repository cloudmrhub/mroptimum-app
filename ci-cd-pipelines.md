# CI/CD Workflows - Split Architecture

## Overview

The CI/CD has been optimized with **two separate workflows** that trigger independently:

| Workflow | File | Triggers | Purpose |
|----------|------|----------|---------|
| **Build Images** | `build-images.yml` | Changes in `calculation/src/**` or `Dockerfile*` | Build & push Lambda/Fargate images to ECR |
| **Deploy & Register** | `deploy-mode1.yml` | Changes in `template.yaml`, `calculation/template.yaml`, or workflow files | Deploy stack and register computing unit |

## Why Split?

### Benefits

1. **Faster Feedback** - Template changes don't wait for Docker builds
2. **Independent Scaling** - Scale each job independently if needed
3. **Cost Savings** - Avoid unnecessary rebuilds
4. **Decoupled Logic** - Clear separation of concerns

### Shared Information

Both workflows use:
- **AWS Account ID** - Constructed independently from credentials
- **Image URIs** - Deploy always uses `:latest` tag from ECR
- **Region** - Fixed as `us-east-1` (env var)
- **Repository Names** - Consistent naming: `mroptimum-lambda` and `mroptimum-fargate`

This design means:
- **No artifacts to share** between workflows
- **No dependency** between build and deploy
- **Latest images always used** - Deploy gets whatever was last pushed

## Workflow Details

### Workflow 1: Build Images (`build-images.yml`)

**Triggers on:**
```yaml
paths:
  - 'calculation/src/**'          # Application code changes
  - 'calculation/Dockerfile*'     # Dockerfile changes
  - '.github/workflows/build-images.yml'  # Workflow changes
```

**What it does:**
1. Checkout code
2. Configure AWS credentials (via OIDC)
3. Login to ECR
4. Build Lambda and Fargate images
5. Push images with:
   - Timestamped tag: `COMMIT_HASH-YYYYMMDD-HHMMSS`
   - Latest tag: `latest` (always points to most recent)

**Output:**
- `mroptimum-lambda:latest` in ECR
- `mroptimum-fargate:latest` in ECR

**Example Run:**
```
When you push to calculation/src/app.py:
  → build-images.yml triggers
  → Images built and tagged with latest
  → ~10-15 min
```

### Workflow 2: Deploy & Register (`deploy-mode1.yml`)

**Triggers on:**
```yaml
paths:
  - 'template.yaml'               # Root stack template
  - 'calculation/template.yaml'   # Nested stack template
  - '.github/workflows/deploy-mode1.yml'  # Workflow changes
  - 'calculation/src/handler.py'  # Handler changes need re-deploy
```

**What it does:**
1. Checkout code
2. Configure AWS credentials (via OIDC)
3. Construct image URIs using `:latest` tag
4. Build SAM template
5. Deploy stack to CloudFormation
6. Extract outputs (State Machine ARN, bucket names)
7. Register computing unit with CloudMR Brain

**Output:**
- Deployed CloudFormation stack
- Registered computing unit with CloudMR Brain API

**Example Run:**
```
When you push to template.yaml:
  → deploy-mode1.yml triggers
  → Uses existing :latest images from ECR
  → Deploys new stack
  → ~5-10 min (no image build)
```

## Workflow Triggers

### Scenario 1: Update Calculation Code

```bash
git commit -m "Update alpha angle calculation"
git push
```

**Result:**
- ✅ `build-images.yml` triggers
- ❌ `deploy-mode1.yml` does NOT trigger
- New images pushed to ECR with `:latest` tag
- Previous deploy keeps running until manually updated

**To deploy with new images:**
```bash
# Option 1: Trigger deploy manually via GitHub Actions UI
# Or Option 2: Make a template change
git touch template.yaml
git commit -m "Trigger deploy"
git push
```

### Scenario 2: Update CloudFormation Template

```bash
git commit -m "Add new Lambda environment variable"
git push
```

**Result:**
- ❌ `build-images.yml` does NOT trigger
- ✅ `deploy-mode1.yml` triggers
- Uses existing `:latest` images (already built)
- Stack redeployed with new template
- No wait for Docker builds

### Scenario 3: Update Both

```bash
git commit -m "Update calculation and add new template parameter"
git push
```

**Result:**
- ✅ `build-images.yml` triggers
- ✅ `deploy-mode1.yml` triggers (independently, may run in parallel)
- Images built first
- Deploy uses newly built images

> **Note**: Workflows run in parallel. If deploy runs before build completes, it will use previous `:latest` images. Re-run deploy after build finishes if needed.

## Manual Workflow Dispatch

### Build Images Manually

```bash
# GitHub UI: Actions → "Build & Push Docker Images" → "Run workflow"
```

Use when:
- You want to rebuild images without code changes
- Docker dependencies updated
- Rebuild for quality/security reasons

### Deploy Manually

```bash
# GitHub UI: Actions → "Mode 1 - Deploy & Register" → "Run workflow" → select options:
```

**Options:**
- `force_rebuild`: Rebuild images even if no calculation/ changes
- `skip_register`: Only deploy stack, don't register with CloudMR Brain

Use when:
- Template changes but you want to skip registration
- Stack failed and needs re-deployment
- Manual testing/debugging

## Environment & Secrets

### Required Secrets (Both Workflows)

| Secret | Used By | Purpose |
|--------|---------|---------|
| `AWS_DEPLOY_ROLE_ARN` | Both | OIDC role for AWS auth |
| `SUBNET_ID_1` | Deploy | Fargate subnet |
| `SUBNET_ID_2` | Deploy | Fargate subnet |
| `SECURITY_GROUP_ID` | Deploy | ECS security group |

### Required Secrets (Deploy Only)

| Secret | Purpose |
|--------|---------|
| `CLOUDMR_API_URL` | CloudMR Brain API endpoint |
| `CLOUDMR_ADMIN_EMAIL` | Auto-refresh token (recommended) |
| `CLOUDMR_ADMIN_PASSWORD` | Auto-refresh token (recommended) |
| OR `CLOUDMR_ADMIN_TOKEN` | Static token (legacy) |

### Environment Variables (Both Workflows)

```yaml
AWS_REGION: us-east-1
STACK_NAME: mroptimum-app-test
CLOUDMR_BRAIN_STACK: cloudmrhub-brain
LAMBDA_REPO: mroptimum-lambda
FARGATE_REPO: mroptimum-fargate
APP_NAME: "MR Optimum"
```

## Troubleshooting

### Build Completes But Deploy Uses Old Images

**Problem:** Deploy step uses old `:latest` tag

**Reason:** Build and Deploy ran in parallel, and Deploy started before Build finished

**Solution:** Re-run Deploy manually after Build completes:
1. Wait for "Build & Push Docker Images" workflow to complete
2. Go to "Mode 1 - Deploy & Register" workflow
3. Click "Run workflow"
4. Confirm both jobs complete successfully

### Deploy Triggers When It Shouldn't

**Problem:** Template changes trigger unnecessary deploy

**Solution:** Update the `paths` filter in `deploy-mode1.yml` to be more specific:

```yaml
paths:
  - 'template.yaml'               # Only root template
  - 'calculation/template.yaml'   # Only nested template
  - '.github/workflows/deploy-mode1.yml'  # Workflow itself
```

Currently includes `calculation/src/handler.py` because handler changes need re-deployment. Remove if you want deploy only on SAM template changes.

### Images Built But Never Used

**Problem:** You built new images but stack still uses old ones

**Reason:** SAM didn't deploy (no template changes)

**Solution:** Either:
1. Make a template change to trigger deploy, or
2. Manually trigger deploy workflow:
   - GitHub UI → "Mode 1 - Deploy & Register" → "Run workflow"

## Quick Commands

```bash
# Push code change (triggers build)
git add calculation/src/
git commit -m "Update alpha angle calculation"
git push

# Push template change (triggers deploy with latest images)
git add template.yaml
git commit -m "Add new Lambda env var"
git push

# Push both (triggers both workflows)
git add calculation/src/ template.yaml
git commit -m "Update code and template"
git push

# Force deploy without waiting for build
# GitHub UI → Actions → Deploy → Run workflow → force_rebuild=false → Run
```

## Diagram

```
Code Push
    ↓
    ├─→ [Changes in calculation/src/**] → build-images.yml
    │                                          ↓
    │                                   Build & push images:latest
    │                                          ↓
    │                                   (Deploy can use new images)
    │
    └─→ [Changes in template.yaml] → deploy-mode1.yml
                                           ↓
                                    Use images:latest from ECR
                                           ↓
                                    Deploy CloudFormation
                                           ↓
                                    Register with CloudMR Brain
```