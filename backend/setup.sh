MYROOT=$(pwd)
echo "Current working directory: $MYROOT"

STACK_NAME=mroptimum-app-test

# 1) Set AWS region & account ID
AWS_REGION="us-east-1"
# ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --profile nyu)" 


# 2) ECR repo names (you can change these)
LAMBDA_REPO="mroptimum-run-job-lambda"
FARGATE_REPO="mroptimum-run-job-fargate"

# 3) Full ECR URIs
LAMBDA_IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${LAMBDA_REPO}:latest"
FARGATE_IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FARGATE_REPO}:latest"


echo "🔎 Using AWS Account: $ACCOUNT_ID, Region: $AWS_REGION"
echo "Lambda image URI:   $LAMBDA_IMAGE_URI"
echo "Fargate image URI:  $FARGATE_IMAGE_URI"

# 4) Ensure ECR repos exist (create them if they don’t)
for REPO in "${LAMBDA_REPO}" "${FARGATE_REPO}"; do
  # 1) Check if the repo exists
  if ! aws ecr describe-repositories --profile nyu \
        --repository-names "${REPO}" \
        --region "${AWS_REGION}" >/dev/null 2>&1; then
    # 2) If it does NOT exist, create it (ignore “AlreadyExists” on retry):
    aws ecr create-repository --profile nyu \
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
  --profile nyu \
  || echo "✅ Step Functions service-linked role already exists"

  
# 5) Authenticate Docker to ECR
aws ecr get-login-password --region "${AWS_REGION}" --profile nyu\
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "✅ Docker authenticated to ECR"

cd "$MYROOT/calculation/src"
# 6) Build & push the Fargate image (fargate-image stage in your Dockerfile)
echo "⏳ Building and pushing Fargate image…"
docker build -t "${FARGATE_REPO}:latest"  -f DockerfileFargate .
docker tag "${FARGATE_REPO}:latest" "${FARGATE_IMAGE_URI}"
docker push "${FARGATE_IMAGE_URI}"
echo "✅ Fargate image pushed: ${FARGATE_IMAGE_URI}"


# # 7) Build & push the Lambda image (lambda-image stage)
# echo "⏳ Building and pushing Lambda image…"
# docker build -t "${LAMBDA_REPO}:latest" -f DockerfileLambda .
  

# docker tag "${LAMBDA_REPO}:latest" "${LAMBDA_IMAGE_URI}"
# docker push "${LAMBDA_IMAGE_URI}"
# echo "✅ Lambda image pushed: ${LAMBDA_IMAGE_URI}"


# 8) Summarize
echo
echo "----------------------------------"
echo " Lambda Image URI:   ${LAMBDA_IMAGE_URI}"
echo " Fargate Image URI:  ${FARGATE_IMAGE_URI}"
echo "----------------------------------"


cd $MYROOT
echo "Current working directory: $MYROOT   " 
pwd

echo "Setting up AWS resources for mroptimum-app-test stack..."
# 9) Set up AWS resources for the stack
VPC=$(aws ec2 describe-vpcs   --query "Vpcs[0].VpcId" --output text --profile nyu)

echo VPC=$VPC
# SUBNET=$(aws ec2 describe-subnets \
#   --filters "Name=vpc-id,Values=$VPC" \
#   --query "Subnets[?MapPublicIpOnLaunch==\`true\`].SubnetId" \
#   --output text \
#   --profile nyu)
# echo SUBNET= $SUBNET


mapfile -t ss < <(
  aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC" \
    --query "Subnets[?MapPublicIpOnLaunch==\`true\`].[SubnetId,AvailabilityZone]" \
    --output text \
    --profile nyu
)

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
echo SUBNETS=$SUBNET
# split into two variables
IFS=, read -r SUBNET1 SUBNET2 <<< "$SUBNET"
echo "SUBNET1=$SUBNET1  SUBNET2=$SUBNET2"

SECURITY_GROUP=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC" "Name=group-name,Values=default" \
  --query "SecurityGroups[0].GroupId" --output text --profile nyu)

echo SECURITY_GROUP=$SECURITY_GROUP



cd $MYROOT
pwd
sam build --profile nyu --use-container


 sam deploy \
  --stack-name "${STACK_NAME}" \
  --profile nyu \
  --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
  --resolve-image-repos \
  --resolve-s3 \
  --parameter-overrides \
    CortexHost=cancelit-env-1.eba-pmamcuv5.us-east-1.elasticbeanstalk.com \
    FargateImageUri="${FARGATE_IMAGE_URI}" \
    LambdaImageUri="${LAMBDA_IMAGE_URI}" \
    ECSClusterName=run-job-cluster \
    SubnetId1="${SUBNET1}" \
    SubnetId2="${SUBNET2}" \
    SecurityGroupIds="${SECURITY_GROUP}" \
  --region "$AWS_REGION" \


PARENT_OUTPUT=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='QueueJobApiKeyID'].OutputValue" \
  --output text\
  --profile nyu)
echo "ApiKeyId = ${PARENT_OUTPUT}"

key=$(aws apigateway get-api-key \
  --api-key "${PARENT_OUTPUT}" \
  --include-value \
  --query 'value' \
  --output text \
  --profile nyu)

echo "ApiKey = ${key}"
