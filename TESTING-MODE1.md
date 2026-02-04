# Mode 1 Testing Guide

This guide will help you test Mode 1 deployment on your local AWS account.

## Prerequisites Check Results

✅ **AWS Account**: `xxxxxxxxxxxxx` (Profile: nyu)  
✅ **SAM CLI**: Installed  
✅ **CloudMR Brain Stack**: `xxxx-brain` (found)  
⚠️ **Docker**: Installed but not running  
⚠️ **VPC**: No default VPC (will use xxx-vpc)  
⚠️ **ECR**: Repositories don't exist yet

## Step-by-Step Testing

### 1. Start Docker

```bash
sudo systemctl start docker
# OR on older systems:
sudo service docker start

# Verify
docker info
```

### 2. Create ECR Repositories

```bash
cd /data/mroptimum-app
AWS_PROFILE=nyu ./scripts/create-ecr-repos.sh
```

This creates:
- `mroptimum-lambda` (private ECR)
- `mroptimum-fargate` (private ECR)

### 3. Get VPC and Subnet Information

```bash
# Use xxxxxxxxxxxxx-vpc
VPC_ID="vpc-xxxxxxxxxxxxx"

# Get public subnets in that VPC
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --profile nyu \
  --region us-east-1 \
  --query "Subnets[*].[SubnetId, AvailabilityZone, CidrBlock, MapPublicIpOnLaunch]" \
  --output table
```

Choose 2 subnets (preferably with `MapPublicIpOnLaunch=True`)

### 4. Build and Push Docker Images

```bash
cd /data/mroptimum-app
AWS_PROFILE=nyu ./scripts/build-and-push-local.sh
```

This will:
- Build Lambda Docker image (~5-10 minutes)
- Build Fargate Docker image (~5-10 minutes)
- Push both to ECR

**Expected output:**
```
Lambda URI:  xxxxxxxxxxxxx.dkr.ecr.us-east-1.amazonaws.com/mroptimum-lambda:latest
Fargate URI: xxxxxxxxxxxxx.dkr.ecr.us-east-1.amazonaws.com/mroptimum-fargate:latest
```

### 5. Deploy Mode 1 Stack

Edit the deployment script to use correct parameters:

```bash
cd /data/mroptimum-app

# Set environment variables
export AWS_PROFILE=nyu
export AWS_REGION=us-east-1
export STACK_NAME=xxx-app-test
export CLOUDMR_BRAIN_STACK=xxxxxxxxxxxxx-brain

# Deploy
./scripts/deploy-mode1-local.sh
```

When prompted for networking, provide:
- **VPC**: `vpc-xxxx` (xxxxxxxxxxxxx-vpc)
- **Subnet 1**: (from step 3)
- **Subnet 2**: (from step 3)
- **CloudMR Host**: `api.xxxxxxxxxxxxx.com` (or your host)

**Deployment time**: ~5-10 minutes

### 6. Test Job Execution

Once deployed, get the State Machine ARN:

```bash
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
  --stack-name mroptimum-app-test \
  --profile nyu \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`CalculationStateMachineArn`].OutputValue' \
  --output text)

echo $STATE_MACHINE_ARN
```

Test execution:

```bash
./scripts/test-job-execution.sh $STATE_MACHINE_ARN
```

This will:
1. Use `calculation/event.json` as test input
2. Start Step Functions execution
3. Monitor progress
4. Show results or errors

### 7. Register with CloudMR Brain

Once testing is successful, register the computing unit:

```bash
# Get your admin token from CloudMR Brain
ADMIN_TOKEN="your-admin-token-here"

curl -X POST "https://api.xxxxxxxxxxxxx.com/api/computing-unit/register" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "appId": "mroptimum",
    "mode": "mode1",
    "provider": "xxxxxxxxxxxxx",
    "awsAccountId": "xxxxxxxxxxxxx",
    "region": "us-east-1",
    "stateMachineArn": "'"$STATE_MACHINE_ARN"'",
    "resultsBucket": "cloudmr-results-xxxxxxxxxxxxx-brain-us-east-1",
    "failedBucket": "cloudmr-failed-xxxxxxxxxxxxx-brain-us-east-1",
    "dataBucket": "cloudmr-data-xxxxxxxxxxxxx-brain-us-east-1",
    "isDefault": true,
    "isShared": true
  }'
```

## Quick Command Reference

### Re-run prerequisites check
```bash
AWS_PROFILE=nyu CLOUDMR_BRAIN_STACK=xxxxxxxxxxxxx-brain ./scripts/test-mode1-prerequisites.sh
```

### View CloudFormation events
```bash
aws cloudformation describe-stack-events \
  --stack-name xxx-app-test \
  --profile nyu \
  --region us-east-1 \
  --max-items 10
```

### View Lambda logs
```bash
# Get Lambda function name from stack
LAMBDA_FUNCTION=$(aws cloudformation describe-stack-resources \
  --stack-name xxx-app-test \
  --profile nyu \
  --region us-east-1 \
  --query "StackResources[?ResourceType=='AWS::Lambda::Function'].PhysicalResourceId" \
  --output text | head -1)

# View logs
aws logs tail "/aws/lambda/$LAMBDA_FUNCTION" --follow --profile nyu --region us-east-1
```

### View ECS task logs
```bash
aws logs tail "/ecs/mroptimum-app-test-fargate" --follow --profile nyu --region us-east-1
```

### Delete stack (cleanup)
```bash
aws cloudformation delete-stack \
  --stack-name mroptimum-app-test \
  --profile nyu \
  --region us-east-1
```

## Troubleshooting

### Docker build fails
- **Error**: `Cannot connect to Docker daemon`
  - **Fix**: Start Docker (`sudo systemctl start docker`)

### ECR push fails
- **Error**: `denied: User is not authenticated`
  - **Fix**: Login to ECR again
  ```bash
  aws ecr get-login-password --profile nyu --region us-east-1 | \
    docker login --username AWS --password-stdin xxxxxxxxxxxxx.dkr.ecr.us-east-1.amazonaws.com
  ```

### SAM deploy fails with "Export not found"
- **Error**: `Export cloudmr-brain-DataBucketName not found`
  - **Fix**: Set correct stack name
  ```bash
  export CLOUDMR_BRAIN_STACK=xxxxxxxxxxxxx-brain
  ```

### ECS task fails to start
- **Error**: `CannotPullContainerError`
  - **Fix**: Ensure subnets have internet access and NAT gateway
  - Check security group allows outbound HTTPS (port 443)

### Job execution times out
- Check CloudWatch Logs for the specific task
- Verify S3 bucket permissions
- Check data files exist and are accessible

## Next Steps

Once Mode 1 testing is successful:

1. **Set up CI/CD**: Configure GitHub Actions using [deploy.yml](.github/workflows/deploy.yml)
2. **Create ECR public repos**: For Mode 2 user distribution
3. **Test Mode 2**: Deploy to a separate AWS account using [mode2-deployment/](mode2-deployment/)
4. **Update frontend**: Add mode selector in mroptimum-webgui

## Support

If you encounter issues not covered here:
1. Check CloudWatch Logs
2. Review CloudFormation events
3. Verify IAM permissions
4. Check networking (VPC/subnets/security groups)
