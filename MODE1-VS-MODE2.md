# Mode 1 vs Mode 2: Visual Comparison

## Overview

MR Optimum supports two deployment modes that integrate with CloudMR Brain.

---

## Quick Comparison Table

| Aspect | Mode 1 (CloudMRHub) | Mode 2 (User-Owned) |
|--------|---------------------|---------------------|
| **Who deploys?** | CloudMRHub (already done) | You (this guide) |
| **Where runs?** | CloudMRHub AWS account | YOUR AWS account |
| **Who pays?** | CloudMRHub | YOU |
| **Data location** | CloudMRHub S3 buckets | YOUR S3 buckets |
| **Cost per job** | Free for you | ~$0.03-$0.05 |
| **Setup time** | 0 minutes (ready now) | ~10 minutes |
| **Resource limits** | Shared | Dedicated |
| **Data sovereignty** | Data in CloudMRHub account | Data stays in your account |
| **Control** | Standard configuration | Full control (customize) |
| **When to use?** | Quick jobs, testing | Heavy workloads, compliance |

---

## Architecture Diagrams

### Mode 1: CloudMRHub Managed

```
┌─────────────────────────────────────────────────────────────────┐
│                      YOUR BROWSER                               │
│  (CloudMR Brain Web Interface)                                  │
└────────────────────┬────────────────────────────────────────────┘
                     │ Submit Job (Mode 1)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                  CloudMR Brain API                              │
│  • Receives job request                                         │
│  • Looks up Mode 1 computing unit                              │
│  • Invokes State Machine in CloudMRHub account                 │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
╔═════════════════════════════════════════════════════════════════╗
║          CloudMRHub AWS Account (262361552878)                  ║
║                                                                 ║
║  ┌─────────────────────────────────────────────────────────┐  ║
║  │  Step Functions State Machine                           │  ║
║  │  arn:aws:states:us-east-1:262361552878:...             │  ║
║  └──────────┬──────────────────────────┬───────────────────┘  ║
║             │                          │                       ║
║    ┌────────▼────────┐        ┌───────▼──────────┐           ║
║    │ Lambda Function │        │ Fargate Task     │           ║
║    │ (Small jobs)    │        │ (Large jobs)     │           ║
║    │ < 15 min        │        │ Up to hours      │           ║
║    │ < 10GB RAM      │        │ Up to 120GB RAM  │           ║
║    └────────┬────────┘        └───────┬──────────┘           ║
║             │                          │                       ║
║             └──────────┬───────────────┘                       ║
║                        ▼                                       ║
║  ┌─────────────────────────────────────────────────────────┐  ║
║  │  S3 Buckets (CloudMRHub owned)                         │  ║
║  │  • cloudmr-data-cloudmrhub-brain-us-east-1            │  ║
║  │  • cloudmr-results-cloudmrhub-brain-us-east-1         │  ║
║  │  • cloudmr-failed-cloudmrhub-brain-us-east-1          │  ║
║  └─────────────────────┬───────────────────────────────────┘  ║
╚════════════════════════┼═══════════════════════════════════════╝
                         │ Results stored
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  CloudMR Brain Database                                         │
│  • Stores job metadata                                          │
│  • Generates presigned URLs for downloads                      │
└────────────────────┬────────────────────────────────────────────┘
                     │ Presigned URL
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  YOUR BROWSER downloads results from CloudMRHub S3              │
└─────────────────────────────────────────────────────────────────┘
```

---

### Mode 2: User-Owned

```
┌─────────────────────────────────────────────────────────────────┐
│                      YOUR BROWSER                               │
│  (CloudMR Brain Web Interface)                                  │
└────────────────────┬────────────────────────────────────────────┘
                     │ Submit Job (Mode 2)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                  CloudMR Brain API                              │
│  • Receives job request                                         │
│  • Looks up Mode 2 computing unit                              │
│  • Assumes cross-account role in YOUR account                  │
│  • Invokes State Machine in YOUR account                       │
└────────────────────┬────────────────────────────────────────────┘
                     │ AssumeRole + StartExecution
                     ▼
╔═════════════════════════════════════════════════════════════════╗
║              YOUR AWS Account (123456789012)                    ║
║                                                                 ║
║  ┌─────────────────────────────────────────────────────────┐  ║
║  │  Step Functions State Machine                           │  ║
║  │  arn:aws:states:us-east-1:123456789012:...             │  ║
║  └──────────┬──────────────────────────┬───────────────────┘  ║
║             │                          │                       ║
║    ┌────────▼────────┐        ┌───────▼──────────┐           ║
║    │ Lambda Function │        │ Fargate Task     │           ║
║    │ (Small jobs)    │        │ (Large jobs)     │           ║
║    │ < 15 min        │        │ Up to hours      │           ║
║    │ < 10GB RAM      │        │ Up to 120GB RAM  │           ║
║    └────────┬────────┘        └───────┬──────────┘           ║
║             │                          │                       ║
║             └──────────┬───────────────┘                       ║
║                        ▼                                       ║
║  ┌─────────────────────────────────────────────────────────┐  ║
║  │  S3 Buckets (YOU own and pay for)                      │  ║
║  │  • mroptimum-mode2-data-123456789012                   │  ║
║  │  • mroptimum-mode2-results-123456789012                │  ║
║  │  • mroptimum-mode2-failed-123456789012                 │  ║
║  └─────────────────────┬───────────────────────────────────┘  ║
║                        │                                       ║
║                        │ Callback Lambda                       ║
║                        ▼                                       ║
║  ┌─────────────────────────────────────────────────────────┐  ║
║  │  Callback Lambda (notifies CloudMR Brain)              │  ║
║  │  POST /api/job/{jobId}/callback                        │  ║
║  └─────────────────────────────────────────────────────────┘  ║
╚════════════════════════┼═══════════════════════════════════════╝
                         │ Job complete notification
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  CloudMR Brain Database                                         │
│  • Updates job status                                           │
│  • Assumes cross-account role to generate presigned URL        │
└────────────────────┬────────────────────────────────────────────┘
                     │ Presigned URL (to YOUR S3)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  YOUR BROWSER downloads results from YOUR S3                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Deployment Process

### Mode 1: Already Deployed ✅

```
[CloudMRHub Team]
      ↓
   Deploys infrastructure in CloudMRHub account
      ↓
   Registers Mode 1 computing unit
      ↓
   YOU: Just use it! (no setup needed)
```

### Mode 2: You Deploy

```
[YOU]
      ↓
1. Run: cd mode2-deployment/ && ./deploy-mode2.sh
      ↓
   Creates CloudFormation stack in YOUR AWS account
      ↓
2. Auto-registration Lambda runs (or manual: ./scripts/register-mode2.sh)
      ↓
   Computing unit registered with CloudMR Brain
      ↓
3. Submit jobs via CloudMR Brain UI (select Mode 2)
      ↓
   Jobs run in YOUR infrastructure
```

---

## Cost Breakdown

### Mode 1: FREE (for you)

- CloudMRHub pays for all compute
- No AWS charges to you
- Shared resources (fair use policy)

### Mode 2: YOU PAY

**Per-Job Estimate:**

| Resource | Usage (10-min job, 4 vCPU, 8GB) | Cost |
|----------|--------------------------------|------|
| Fargate vCPU | 4 vCPU × $0.04/hr × (10/60) hr | $0.027 |
| Fargate RAM | 8 GB × $0.004/GB/hr × (10/60) hr | $0.005 |
| Lambda | Included (if < 15 min) | $0.00 |
| S3 Storage | ~100MB × $0.023/GB/month | $0.002 |
| Step Functions | 1 execution × $0.025/1K | $0.00 |
| **Total per job** | | **~$0.03-$0.05** |

**Monthly Estimate (100 jobs):**

- 100 jobs × $0.04 = **~$4/month**
- Plus S3 storage (~$2/month if you keep results)
- **Total: ~$6/month for 100 jobs**

---

## Data Flow

### Mode 1: Data flows through CloudMRHub

```
Input Data → CloudMRHub S3 → Processing → CloudMRHub S3 → Download
            (temporary)                    (results)
```

### Mode 2: Data stays in your account

```
Input Data → YOUR S3 → Processing (YOUR compute) → YOUR S3 → Download
            (you control)                          (you control)
```

---

## Security & Compliance

### Mode 1: Trust CloudMRHub

- ✅ Data processed in CloudMRHub infrastructure
- ✅ CloudMRHub manages security
- ❌ Data leaves your AWS account
- ❌ Not suitable for HIPAA/regulated data

### Mode 2: You Control Everything

- ✅ Data never leaves your AWS account
- ✅ You manage all security policies
- ✅ HIPAA/SOC2 compliant (if your AWS is)
- ✅ Cross-account role has minimal permissions
- ✅ Full audit trail in YOUR CloudTrail

---

## When to Use Each Mode

### Use Mode 1 if:

- 🎯 You want to get started immediately
- 🎯 You're testing/prototyping
- 🎯 You have < 100 jobs/month
- 🎯 You don't have AWS infrastructure
- 🎯 You trust CloudMRHub with your data

### Use Mode 2 if:

- 🎯 You need data sovereignty
- 🎯 You have compliance requirements (HIPAA, SOC2)
- 🎯 You're processing sensitive/regulated data
- 🎯 You need dedicated resources (no sharing)
- 🎯 You want to optimize costs at scale
- 🎯 You want full control over infrastructure

---

## Resource Limits

### Mode 1: Shared Resources

| Resource | Limit |
|----------|-------|
| Lambda CPU | 2 vCPU |
| Lambda RAM | 10 GB |
| Lambda timeout | 15 minutes |
| Fargate CPU | Up to 16 vCPU (shared) |
| Fargate RAM | Up to 120 GB (shared) |
| Concurrent jobs | Fair use (shared queue) |

### Mode 2: Your Resources

| Resource | Limit |
|----------|-------|
| Lambda CPU | 2 vCPU |
| Lambda RAM | 10 GB |
| Lambda timeout | 15 minutes |
| Fargate CPU | **Up to 16 vCPU (dedicated)** |
| Fargate RAM | **Up to 120 GB (dedicated)** |
| Concurrent jobs | **Your AWS account limits** |

---

## Summary

| Decision Factor | Choose Mode 1 | Choose Mode 2 |
|----------------|---------------|---------------|
| **Cost** | Free | ~$0.03/job |
| **Setup time** | 0 minutes | 10 minutes |
| **Data control** | CloudMRHub | You |
| **Compliance** | No | Yes (HIPAA/SOC2) |
| **Resource dedication** | Shared | Dedicated |
| **Scale** | Fair use | Your limits |
| **Best for** | Testing, small workloads | Production, regulated data |

---

## Next Steps

### To Deploy Mode 2:

1. Read: `MODE2-QUICK-START.md` (2-minute read)
2. Run: `cd mode2-deployment/ && ./deploy-mode2.sh`
3. Verify: `./scripts/register-mode2.sh`
4. Test: Submit a job via CloudMR Brain UI

### For More Details:

- **Quick Start**: `MODE2-QUICK-START.md`
- **Full Guide**: `MODE2-DEPLOYMENT-GUIDE.md`
- **Scripts**: `scripts/register-mode2.sh`, `scripts/mode2-quick-reference.sh`
