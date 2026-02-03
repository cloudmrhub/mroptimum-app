# MR Optimum Mode 2 - User Deployment Guide

This package allows you to deploy MR Optimum compute infrastructure in **your own AWS account**.

## Why Mode 2?

| Feature | Mode 1 (Default) | Mode 2 (Your Account) |
|---------|------------------|----------------------|
| Where compute runs | CloudMRHub's AWS | Your AWS |
| Who pays | CloudMRHub | You |
| Data location | CloudMRHub's S3 | Your S3 |
| Resource limits | Shared | Dedicated |
| Data sovereignty | ❌ | ✅ |

## Prerequisites

1. **AWS Account** with admin access
2. **AWS CLI** installed and configured
3. **CloudMR Account** with valid token
4. **VPC** with at least 2 public subnets (internet access required)

## Quick Start

### Option 1: Interactive Deployment

```bash
./deploy-mode2.sh
```

The script will prompt you for:
- Your CloudMR user token (from https://cloudmrhub.com/profile)
- VPC and subnet selection

### Option 2: Non-Interactive Deployment

```bash
./deploy-mode2.sh \
    --stack-name my-mroptimum \
    --region us-west-2 \
    --image-tag v1.2.3
```

### Option 3: AWS Console

1. Go to AWS CloudFormation Console
2. Click "Create stack" → "With new resources"
3. Upload `template-mode2.yaml`
4. Fill in parameters
5. Acknowledge IAM capabilities
6. Create stack

## What Gets Deployed

```
Your AWS Account
├── S3 Buckets
│   ├── {stack-name}-results-{account-id}
│   ├── {stack-name}-failed-{account-id}
│   └── {stack-name}-data-{account-id}
├── ECS Cluster
│   └── Fargate tasks (for heavy computation)
├── Lambda Functions
│   ├── RunJobLambda (fast computations)
│   ├── PlatformSelector (routes jobs)
│   ├── Registration (auto-registers with CloudMR)
│   └── Callback (notifies CloudMR on completion)
├── Step Functions State Machine
│   └── Orchestrates Lambda/Fargate
├── IAM Roles
│   ├── Lambda execution roles
│   ├── ECS task roles
│   └── Cross-account role (for CloudMR Brain)
└── CloudWatch Log Groups
```

## How It Works

1. **You schedule a job** via MR Optimum web interface (select Mode 2)
2. **CloudMR Brain** looks up your computing unit and assumes the cross-account role
3. **Step Functions** is invoked in YOUR account
4. **Lambda or Fargate** runs the SNR calculation
5. **Results** are written to YOUR S3 bucket
6. **Callback Lambda** notifies CloudMR Brain the job is complete
7. **Frontend** fetches presigned URL (generated via cross-account access) to download results

```
┌─────────────────┐          ┌─────────────────┐
│  CloudMRHub     │  ──1──▶  │  Your Account   │
│  (cloudmr-brain)│          │  (Step Functions)│
│                 │  ◀─6───  │                 │
│  Stores result  │          │  Runs compute   │
│  metadata       │          │  Stores results │
└─────────────────┘          └─────────────────┘
        │
        │ 7. Presigned URL
        ▼
┌─────────────────┐
│  Your Browser   │
│  (Downloads     │
│   from YOUR S3) │
└─────────────────┘
```

## Security

### Cross-Account Access

CloudMR Brain needs permission to:
- Start Step Functions executions in your account
- Generate presigned URLs for your S3 buckets

This is implemented via **IAM Role Assumption with External ID**:

```yaml
CrossAccountRole:
  TrustPolicy:
    Principal:
      AWS: arn:aws:iam::CLOUDMR_ACCOUNT:root
    Condition:
      StringEquals:
        sts:ExternalId: cloudmr-YOUR_ACCOUNT-STACK_NAME
```

The External ID prevents [confused deputy attacks](https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html).

### Data Isolation

- Your data stays in YOUR S3 buckets
- CloudMR Brain only stores metadata (job status, bucket names)
- Presigned URLs expire after 1 hour

## Cost Estimation

Mode 2 costs are charged to YOUR AWS account:

| Resource | Estimated Cost | Notes |
|----------|---------------|-------|
| Lambda | ~$0.10/job | For fast jobs (<15 min) |
| Fargate | ~$0.50/job | For heavy jobs (>15 min) |
| S3 Storage | ~$0.023/GB/month | Results + failed outputs |
| S3 Requests | ~$0.005/1000 | PUT/GET operations |

**Example**: 100 jobs/month with 1GB results each ≈ **$15-25/month**

## Configuration Options

### Stack Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `CloudMRApiUrl` | Yes | - | CloudMR Brain API URL |
| `CloudMRUserToken` | Yes | - | Your user token |
| `VpcId` | Yes | - | VPC for Fargate |
| `SubnetId1` | Yes | - | First public subnet |
| `SubnetId2` | Yes | - | Second public subnet |
| `ImageTag` | No | `latest` | Docker image version |
| `ECSClusterName` | No | `mroptimum-mode2-cluster` | ECS cluster name |
| `AppId` | No | `mroptimum` | CloudMR app identifier |

### Image Tags

By default, `latest` is used. For production stability, consider pinning to a specific version:

```bash
./deploy-mode2.sh --image-tag v2.3.1
```

Available tags:
- `latest` - Most recent stable release
- `v2.x.x` - Specific version
- `abc1234` - Git SHA for exact reproducibility

## Management

### View Stack Outputs

```bash
aws cloudformation describe-stacks \
    --stack-name mroptimum-mode2 \
    --query 'Stacks[0].Outputs'
```

### Update Stack

When CloudMRHub releases new images:

```bash
aws cloudformation update-stack \
    --stack-name mroptimum-mode2 \
    --use-previous-template \
    --parameters \
        ParameterKey=ImageTag,ParameterValue=v2.4.0 \
        ParameterKey=CloudMRUserToken,UsePreviousValue=true \
        ...
```

Or use the deployment script:

```bash
./deploy-mode2.sh --image-tag v2.4.0
```

### Delete Stack

```bash
aws cloudformation delete-stack --stack-name mroptimum-mode2
```

**Note**: S3 buckets must be empty before deletion. To force delete with contents:

```bash
# Empty buckets first
aws s3 rm s3://mroptimum-mode2-results-123456789012 --recursive
aws s3 rm s3://mroptimum-mode2-failed-123456789012 --recursive
aws s3 rm s3://mroptimum-mode2-data-123456789012 --recursive

# Then delete stack
aws cloudformation delete-stack --stack-name mroptimum-mode2
```

## Troubleshooting

### Deployment Fails

**"No public subnets found"**
- Ensure your VPC has subnets with `MapPublicIpOnLaunch=true`
- Or manually specify subnet IDs

**"Invalid CloudMR token"**
- Refresh your token at https://cloudmrhub.com/profile
- Ensure token hasn't expired

**"Template validation error"**
- Ensure AWS CLI is configured for the correct region
- Check you have CloudFormation permissions

### Jobs Not Starting

**"Computing unit not found"**
- Wait a few minutes for registration to propagate
- Check CloudMR Brain `/api/computing-unit/list` includes your unit

**"AssumeRole failed"**
- Verify cross-account role trust policy
- Check External ID matches

### Jobs Failing

**"Container failed to start"**
- Check CloudWatch Logs: `/ecs/{stack-name}-fargate`
- Ensure subnets have internet access (for ECR pull)

**"S3 access denied"**
- Check task role has S3 permissions
- Verify bucket names in environment variables

### Results Not Appearing

**"Callback failed"**
- Check callback Lambda logs
- Verify CloudMR API URL is accessible from your VPC
- Check user token is still valid

## Support

- **Documentation**: https://docs.cloudmrhub.com
- **Issues**: https://github.com/cloudmrhub/mroptimum-app/issues
- **Email**: support@cloudmrhub.com

## License

Copyright © CloudMRHub. All rights reserved.
