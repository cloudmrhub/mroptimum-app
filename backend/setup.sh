#!/bin/bash
set -e

STACK_NAME=mroptimum-app-py-cloudmr
SPINFRONTEND=true
AWS_PROFILE="mode2-account-a-CE"
# 1) Set AWS region & account ID
AWS_REGION="us-east-1"
# ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --profile ${AWS_PROFILE})" 


# 2) ECR repo names (you can change these)
LAMBDA_REPO="mroptimum-run-job-lambda"
FARGATE_REPO="mroptimum-run-job-fargate"

# 2.1) Set these to the output from cloudmr-brain deployment (Account B)
DATA_BUCKET_NAME="cloudmr-data-py-cloudmr-brain-v2-us-east-1"
RESULTS_BUCKET_NAME="cloudmr-results-py-cloudmr-brain-v2-us-east-1"
FAILED_BUCKET_NAME="cloudmr-failed-py-cloudmr-brain-v2-us-east-1"
TRUSTED_ACCOUNT_ID="209479308939" # Set this to  Account B's ID if you want to enable cross-account trust


MYROOT=$(pwd)
echo "Current working directory: $MYROOT"


# 3) Full ECR URIs
LAMBDA_IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${LAMBDA_REPO}:latest"
FARGATE_IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FARGATE_REPO}:latest"


echo "🔎 Using AWS Account: $ACCOUNT_ID, Region: $AWS_REGION"
echo "Lambda image URI:   $LAMBDA_IMAGE_URI"
echo "Fargate image URI:  $FARGATE_IMAGE_URI"

# 4) Ensure ECR repos exist (create them if they don’t)
for REPO in "${LAMBDA_REPO}" "${FARGATE_REPO}"; do
  # 1) Check if the repo exists
  if ! aws ecr describe-repositories --profile ${AWS_PROFILE} \
        --repository-names "${REPO}" \
        --region "${AWS_REGION}" >/dev/null 2>&1; then
    # 2) If it does NOT exist, create it (ignore “AlreadyExists” on retry):
    aws ecr create-repository --profile ${AWS_PROFILE} \
      --repository-name "${REPO}" \
      --region "${AWS_REGION}" \
    || echo "✅ ECR repository '${REPO}' already exists; skipping creation."
  else
    echo "✅ ECR repository '${REPO}' already exists; skipping creation."
  fi
done

echo "🔧 ECR repositories checked/created successfully."

# 4.1) Make sure Step Functions service-linked role exists
aws iam create-service-linked-role \
  --aws-service-name states.amazonaws.com \
  --description "Allows Step Functions to manage EventBridge rules" \
  --profile ${AWS_PROFILE} \
  || echo "✅ Step Functions service-linked role already exists"

  
# 5) Authenticate Docker to ECR
aws ecr get-login-password --region "${AWS_REGION}" --profile ${AWS_PROFILE}\
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "✅ Docker authenticated to ECR"

cd "$MYROOT/calculation/src"
# 6) Build & push the Fargate image (fargate-image stage in your Dockerfile)
echo "⏳ Building and pushing Fargate image…"
docker build -t "${FARGATE_REPO}:latest"  -f DockerfileFargate .
docker tag "${FARGATE_REPO}:latest" "${FARGATE_IMAGE_URI}"
docker push "${FARGATE_IMAGE_URI}"
echo "✅ Fargate image pushed: ${FARGATE_IMAGE_URI}"


# 7) Build & push the Lambda image (lambda-image stage)
echo "⏳ Building and pushing Lambda image…"
docker build -t "${LAMBDA_REPO}:latest" -f DockerfileLambda .
  

docker tag "${LAMBDA_REPO}:latest" "${LAMBDA_IMAGE_URI}"
docker push "${LAMBDA_IMAGE_URI}"
echo "✅ Lambda image pushed: ${LAMBDA_IMAGE_URI}"


# 8) Summarize
echo
echo "----------------------------------"
echo " Lambda Image URI:   ${LAMBDA_IMAGE_URI}"
echo " Fargate Image URI:  ${FARGATE_IMAGE_URI}"
echo "----------------------------------"


cd $MYROOT
echo "Current working directory: $MYROOT   " 
pwd

echo "Setting up AWS resources for $STACK_NAME stack..."
# 9) Set up AWS resources for the stack
echo "🔍 Querying VPC..."
VPC=$(timeout 30 aws ec2 describe-vpcs --region "$AWS_REGION" --query "Vpcs[0].VpcId" --output text --profile ${AWS_PROFILE} 2>&1)

if [ $? -ne 0 ]; then
  echo "❌ Failed to query VPC. Error: $VPC"
  exit 1
fi

if [ -z "$VPC" ] || [ "$VPC" == "None" ]; then
  echo "❌ No VPC found in region $AWS_REGION"
  echo "Please create a VPC first or specify a different region"
  exit 1
fi

echo "✅ VPC=$VPC"
# SUBNET=$(aws ec2 describe-subnets \
#   --filters "Name=vpc-id,Values=$VPC" \
#   --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId" \
#   --output text \
#   --profile ${AWS_PROFILE})
# echo SUBNET= $SUBNET


echo "🔍 Querying subnets..."
# Use a variable instead of mapfile with process substitution to avoid timeout issues
subnet_output=$(timeout 30 aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC" \
  --query "Subnets[?MapPublicIpOnLaunch==\`true\`].[SubnetId,AvailabilityZone]" \
  --output text \
  --region "$AWS_REGION" \
  --profile ${AWS_PROFILE} 2>&1)

if [ $? -ne 0 ]; then
  echo "❌ Failed to query subnets. Error: $subnet_output"
  exit 1
fi

if [ -z "$subnet_output" ]; then
  echo "❌ No public subnets found in VPC $VPC"
  echo "Please create public subnets or check your VPC configuration"
  exit 1
fi

# Read the output into an array
mapfile -t ss <<< "$subnet_output"

# pick one subnet per AZ
declare -A az_seen
selected=()
for entry in "${ss[@]}"; do
  subnet_id=${entry%%$'\t'*}
  az=${entry#*$'\t'}
  if [[ -z "${az_seen[$az]}" ]]; then
    az_seen[$az]=1
    selected+=("$subnet_id")
    (( ${#selected[@]} == 2 )) && break
  fi
done

# join with commas
SUBNET=$(IFS=,; echo "${selected[*]}")

if [ ${#selected[@]} -lt 2 ]; then
  echo "❌ Need at least 2 subnets in different AZs, found only ${#selected[@]}"
  exit 1
fi

echo "✅ SUBNETS=$SUBNET"
# split into two variables
IFS=, read -r SUBNET1 SUBNET2 <<< "$SUBNET"
echo "✅ SUBNET1=$SUBNET1  SUBNET2=$SUBNET2"

echo "🔍 Querying security group..."
SECURITY_GROUP=$(timeout 30 aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC" "Name=group-name,Values=default" \
  --region "$AWS_REGION" \
  --query "SecurityGroups[0].GroupId" --output text --profile ${AWS_PROFILE} 2>&1)

if [ $? -ne 0 ] || [ -z "$SECURITY_GROUP" ] || [ "$SECURITY_GROUP" == "None" ]; then
  echo "❌ Failed to find default security group in VPC $VPC"
  exit 1
fi

echo "✅ SECURITY_GROUP=$SECURITY_GROUP"



cd $MYROOT
pwd
if ! sam build --profile ${AWS_PROFILE} --use-container; then
  echo "❌ SAM build failed"
  exit 1
fi


if ! sam deploy \
  --stack-name "${STACK_NAME}" \
  --profile ${AWS_PROFILE} \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --resolve-s3 \
  --parameter-overrides \
    CortexHost=cancelit-env-1.eba-pmamcuv5.us-east-1.elasticbeanstalk.com \
    FargateImageUri="${FARGATE_IMAGE_URI}" \
    LambdaImageUri="${LAMBDA_IMAGE_URI}" \
    ECSClusterName=run-job-cluster \
    SubnetId1="${SUBNET1}" \
    SubnetId2="${SUBNET2}" \
    SecurityGroupIds="${SECURITY_GROUP}" \
    DataBucketPName="${DATA_BUCKET_NAME}" \
    ResultsBucketPName="${RESULTS_BUCKET_NAME}" \
    FailedBucketPName="${FAILED_BUCKET_NAME}" \
    TrustedAccountID="${TRUSTED_ACCOUNT_ID}" \
  --region "$AWS_REGION" ; then
  echo "❌ SAM deploy failed"
  exit 1
fi



# PARENT_OUTPUT=$(aws cloudformation describe-stacks \
#   --stack-name "${STACK_NAME}" \
#   --query "Stacks[0].Outputs[?OutputKey=='QueueJobApiKeyID'].OutputValue" \
#   --output text \
#   --region "$AWS_REGION" \
#   --profile ${AWS_PROFILE})
# echo "ApiKeyId = ${PARENT_OUTPUT}"

# key=$(aws apigateway get-api-key \
#   --api-key "${PARENT_OUTPUT}" \
#   --include-value \
#   --query 'value' \
#   --output text \
#   --region "$AWS_REGION" \
#   --profile ${AWS_PROFILE})

# echo "ApiKey = ${key}"





# QueueJobApiUrl=$(aws cloudformation describe-stacks \
#   --stack-name "${STACK_NAME}" \
#   --query "Stacks[0].Outputs[?OutputKey=='QueueJobApiUrl'].OutputValue" \
#   --output text\
#   --profile ${AWS_PROFILE})
# echo "QueueJobApiUrl = ${QueueJobApiUrl}"

# FrontendApiUrl=$(aws cloudformation describe-stacks \
#   --stack-name "${STACK_NAME}" \
#   --query "Stacks[0].Outputs[?OutputKey=='FrontendAPI'].OutputValue" \
#   --output text\
#   --profile ${AWS_PROFILE})
# echo "FrontendApiUrl = ${FrontendApiUrl}"



# if $SPINFRONTEND; then
#   echo "Frontend is already running."
# else
#   echo "Starting frontend..."
#   cd "$MYROOT/frontend"
#   npm install
#   npm run dev &
# fi
echo "Setup complete! 🎉"

echo $(date)
