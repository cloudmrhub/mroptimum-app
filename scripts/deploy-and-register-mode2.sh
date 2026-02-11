#!/usr/bin/env bash
#
# Deploy & Register MR Optimum Mode 2 (User-Owned)
#
# This is a single script that:
#   1. Logs in to CloudMR Brain
#   2. Deploys the SAM stack into YOUR AWS account (reusing CloudMR's ECR images)
#   3. Registers the computing unit as mode_2 with CloudMR Brain
#
# The workflow is identical to Mode 1 except:
#   - Infrastructure runs in YOUR AWS account
#   - S3 buckets are created in YOUR account
#   - Computing unit is registered as mode_2
#
# Usage:
#   ./scripts/deploy-and-register-mode2.sh \
#       --email you@example.com \
#       --password 'YourP@ssword' \
#       --profile your-aws-profile
#
# Or with environment variables:
#   export CLOUDMR_EMAIL="you@example.com"
#   export CLOUDMR_PASSWORD="YourP@ssword"
#   export AWS_PROFILE="your-aws-profile"
#   ./scripts/deploy-and-register-mode2.sh
#
# Required:
#   --email / CLOUDMR_EMAIL        CloudMR Brain login email
#   --password / CLOUDMR_PASSWORD  CloudMR Brain login password
#   --profile / AWS_PROFILE        AWS CLI profile for the user's account
#
#   --alias            Alias for the computing unit (default: Mode 2)

set -euo pipefail

# ============================================================================
# Colors
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step()    { echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"; }

# ============================================================================
# Defaults
# ============================================================================
CLOUDMR_EMAIL="${CLOUDMR_EMAIL:-}"
CLOUDMR_PASSWORD="${CLOUDMR_PASSWORD:-}"
AWS_PROFILE="${AWS_PROFILE:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_NAME="${STACK_NAME:-mroptimum-mode2}"
CLOUDMR_API_URL="${CLOUDMR_API_URL:-${CLOUDM_MR_BRAIN:-https://brain.aws.cloudmrhub.com/Prod}}"
APP_NAME="${APP_NAME:-MR Optimum}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ALIAS_DEFAULT="Mode 2"
ALIAS="${ALIAS:-}"

# CloudMR's ECR account (where the Docker images live)
ECR_ACCOUNT="${ECR_ACCOUNT:-469266894233}"
ECR_REGION="${ECR_REGION:-us-east-1}"

# S3 Buckets (default to Mode 1 / CloudMR Brain buckets)
DATA_BUCKET="${DATA_BUCKET:-cloudmr-data-cloudmrhub-brain-us-east-1}"
RESULTS_BUCKET="${RESULTS_BUCKET:-cloudmr-results-cloudmrhub-brain-us-east-1}"
FAILED_BUCKET="${FAILED_BUCKET:-cloudmr-failed-cloudmrhub-brain-us-east-1}"

# ============================================================================
# Parse CLI arguments
# ============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --email)        CLOUDMR_EMAIL="$2";    shift 2 ;;
        --password)     CLOUDMR_PASSWORD="$2"; shift 2 ;;
        --profile)      AWS_PROFILE="$2";      shift 2 ;;
        --region)       AWS_REGION="$2";       shift 2 ;;
        --stack-name)   STACK_NAME="$2";       shift 2 ;;
        --api-url)      CLOUDMR_API_URL="$2";  shift 2 ;;
        --cloudmr-role-arn) CLOUDMR_ROLE_ARN="$2"; shift 2 ;;
        --auto-update-trust) AUTO_UPDATE_TRUST=true; shift 1 ;;
        --yes) ASSUME_YES=true; shift 1 ;;
        --external-id)      EXTERNAL_ID="$2";      shift 2 ;;
        --ecr-account)  ECR_ACCOUNT="$2";      shift 2 ;;
        --ecr-region)   ECR_REGION="$2";       shift 2 ;;
        --image-tag)    IMAGE_TAG="$2";        shift 2 ;;
        --app-name)     APP_NAME="$2";         shift 2 ;;
        --data-bucket)    DATA_BUCKET="$2";     shift 2 ;;
        --results-bucket) RESULTS_BUCKET="$2";  shift 2 ;;
        --failed-bucket)  FAILED_BUCKET="$2";   shift 2 ;;
        --alias)
            ALIAS="$2"; shift 2 ;;
        --s3-bucket)
            S3_BUCKET="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Required (via flags or environment variables):"
            echo "  --email EMAIL           CloudMR Brain email     (or CLOUDMR_EMAIL)"
            echo "  --password PASSWORD     CloudMR Brain password  (or CLOUDMR_PASSWORD)"
            echo "  --profile PROFILE       AWS CLI profile         (or AWS_PROFILE)"
            echo ""
            echo "Optional:"
            echo "  --region REGION         AWS region              (default: us-east-1)"
            echo "  --stack-name NAME       Stack name              (default: mroptimum-mode2)"
            echo "  --api-url URL           CloudMR API URL         (default: brain.aws.cloudmrhub.com)"
            echo "  --ecr-account ID        ECR source account      (default: 469266894233)"
            echo "  --ecr-region REGION     ECR source region       (default: us-east-1)"
            echo "  --image-tag TAG         Docker image tag        (default: latest)"
            echo "  --app-name NAME         CloudMR app name        (default: MR Optimum)"
            echo "  --data-bucket NAME      S3 data bucket          (default: cloudmr-data-cloudmrhub-brain-us-east-1)"
            echo "  --results-bucket NAME   S3 results bucket       (default: cloudmr-results-cloudmrhub-brain-us-east-1)"
            echo "  --failed-bucket NAME    S3 failed bucket        (default: cloudmr-failed-cloudmrhub-brain-us-east-1)"
            echo "  --s3-bucket NAME        S3 bucket to stage SAM artifacts (optional - will be created if missing)"
            echo "  --cloudmr-role-arn ARN Optional: CloudMR's QueueJob role ARN that will assume the cross-account role"
            echo "  --external-id ID       Optional: ExternalId that cloudmr must provide when assuming the role"
            echo "  --auto-update-trust    Automatically update the deployed cross-account role trust policy to include the provided CloudMR role ARN (non-interactive, requires iam:UpdateAssumeRolePolicy)."
            echo "  --yes                  Skip confirmation prompts (useful with --auto-update-trust in CI)."
            echo "\nAfter deployment, the script verifies the deployed cross-account role's trust policy and can update it to explicitly allow the provided CloudMR QueueJob role ARN (requires iam:UpdateAssumeRolePolicy permission)."
            echo "  --alias ALIAS           Alias for computing unit (default: Mode 2)"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

    # Optional explicit S3 bucket to stage artifacts (if not provided, SAM uses a managed bucket)
    S3_BUCKET="${S3_BUCKET:-}"
    CLOUDMR_ROLE_ARN="${CLOUDMR_ROLE_ARN:-}"
    EXTERNAL_ID="${EXTERNAL_ID:-}"
    AUTO_UPDATE_TRUST="${AUTO_UPDATE_TRUST:-false}"
    ASSUME_YES="${ASSUME_YES:-false}"

# ============================================================================
# Build AWS CLI profile argument
# ============================================================================
AWS_ARGS=""
if [[ -n "$AWS_PROFILE" ]]; then
    AWS_ARGS="--profile $AWS_PROFILE"
fi

# ============================================================================
# Banner
# ============================================================================
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     MR Optimum — Mode 2 Deploy & Register                    ║${NC}"
echo -e "${BLUE}║     (User-Owned Infrastructure)                              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# Validate inputs
# ============================================================================
log_step "Step 0: Validate inputs"

for cmd in curl jq aws sam; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "'$cmd' is required but not installed."
        exit 1
    fi
done
log_success "All required tools found (curl, jq, aws, sam)"

if [[ -z "$CLOUDMR_EMAIL" ]]; then
    log_error "CloudMR email not set. Use --email or export CLOUDMR_EMAIL"
    exit 1
fi
if [[ -z "$CLOUDMR_PASSWORD" ]]; then
    log_error "CloudMR password not set. Use --password or export CLOUDMR_PASSWORD"
    exit 1
fi
if [[ -z "$AWS_PROFILE" ]]; then
    log_warn "No AWS profile specified. Using default credentials."
fi

log_success "Inputs validated"

# ============================================================================
# Step 1: Check AWS credentials
# ============================================================================
log_step "Step 1: Check AWS credentials"

if ! USER_AWS_ACCOUNT_ID=$(aws sts get-caller-identity $AWS_ARGS --query Account --output text 2>/dev/null); then
    log_error "Unable to get AWS caller identity."
    if [[ -n "$AWS_PROFILE" ]]; then
        log_info "Try: aws sso login --profile $AWS_PROFILE"
    else
        log_info "Try: aws configure or set AWS_PROFILE"
    fi
    exit 1
fi


log_success "AWS Account:  $USER_AWS_ACCOUNT_ID"
log_info    "AWS Profile:  ${AWS_PROFILE:-default}"
log_info    "AWS Region:   $AWS_REGION"

# ============================================================================
# Step 2: Login to CloudMR Brain
# ============================================================================
log_step "Step 2: Login to CloudMR Brain"

LOGIN_PAYLOAD=$(jq -n \
    --arg email "$CLOUDMR_EMAIL" \
    --arg password "$CLOUDMR_PASSWORD" \
    '{email: $email, password: $password}')

LOGIN_RESPONSE=$(curl -s -X POST "${CLOUDMR_API_URL}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "$LOGIN_PAYLOAD")

LOGIN_SUCCESS=$(echo "$LOGIN_RESPONSE" | jq -r '.success // false')
if [[ "$LOGIN_SUCCESS" != "true" ]]; then
    LOGIN_MSG=$(echo "$LOGIN_RESPONSE" | jq -r '.message // "Unknown error"')
    log_error "Login failed: $LOGIN_MSG"
    exit 1
fi

ID_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.id_token')
USER_ID=$(echo "$LOGIN_RESPONSE" | jq -r '.user_id')

if [[ -z "$ID_TOKEN" || "$ID_TOKEN" == "null" ]]; then
    log_error "Failed to extract ID token from login response"
    exit 1
fi

log_success "Logged in as: $CLOUDMR_EMAIL (user_id: $USER_ID)"

# ============================================================================
# Step 3: Resolve ECR image URIs
# ============================================================================
log_step "Step 3: Resolve ECR image URIs"

ECR_REGISTRY="${ECR_ACCOUNT}.dkr.ecr.${ECR_REGION}.amazonaws.com"
LAMBDA_IMAGE_URI="${ECR_REGISTRY}/mroptimum-lambda:${IMAGE_TAG}"
FARGATE_IMAGE_URI="${ECR_REGISTRY}/mroptimum-fargate:${IMAGE_TAG}"

log_info "Lambda Image:  $LAMBDA_IMAGE_URI"
log_info "Fargate Image: $FARGATE_IMAGE_URI"

# Verify the user's account can pull these images
# (The ECR repo must have a cross-account pull policy, or be public)
log_info "Note: Ensure the ECR repos in account $ECR_ACCOUNT allow pulls from account $USER_AWS_ACCOUNT_ID"

# ============================================================================
# Step 4: Detect networking (VPC, Subnets, Security Group)
# ============================================================================
log_step "Step 4: Detect networking"

# --- VPC ---
VPC_ID="${VPC_ID:-}"
if [[ -z "$VPC_ID" ]]; then
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        $AWS_ARGS --region "$AWS_REGION" \
        --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
    
    if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
        log_warn "No default VPC found. Available VPCs:"
        aws ec2 describe-vpcs $AWS_ARGS --region "$AWS_REGION" \
            --query "Vpcs[*].[VpcId,Tags[?Key=='Name'].Value|[0]||'(no name)',IsDefault]" \
            --output table
        echo ""
        read -rp "Enter VPC ID: " VPC_ID
    fi
fi
log_success "VPC: $VPC_ID"

# --- Subnets ---
SUBNET_ID_1="${SUBNET_ID_1:-}"
SUBNET_ID_2="${SUBNET_ID_2:-}"

if [[ -z "$SUBNET_ID_1" || -z "$SUBNET_ID_2" ]]; then
    SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
        $AWS_ARGS --region "$AWS_REGION" \
        --query "Subnets[*].SubnetId" --output text 2>/dev/null || echo "")
    
    SUBNET_ARRAY=($SUBNETS)
    
    if [[ ${#SUBNET_ARRAY[@]} -lt 2 ]]; then
        # Fall back to all subnets
        SUBNETS=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            $AWS_ARGS --region "$AWS_REGION" \
            --query "Subnets[*].SubnetId" --output text)
        SUBNET_ARRAY=($SUBNETS)
    fi
    
    if [[ ${#SUBNET_ARRAY[@]} -lt 2 ]]; then
        log_warn "Could not auto-detect 2 subnets. Available subnets:"
        aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
            $AWS_ARGS --region "$AWS_REGION" \
            --query "Subnets[*].[SubnetId,AvailabilityZone]" --output table
        read -rp "Subnet 1 ID: " SUBNET_ID_1
        read -rp "Subnet 2 ID: " SUBNET_ID_2
    else
        SUBNET_ID_1="${SUBNET_ID_1:-${SUBNET_ARRAY[0]}}"
        SUBNET_ID_2="${SUBNET_ID_2:-${SUBNET_ARRAY[1]}}"
    fi
fi
log_success "Subnet 1: $SUBNET_ID_1"
log_success "Subnet 2: $SUBNET_ID_2"

# --- Security Group ---
SG_ID="${SECURITY_GROUP_ID:-}"
if [[ -z "$SG_ID" ]]; then
    SG_NAME="mroptimum-mode2-ecs-sg"
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" \
        $AWS_ARGS --region "$AWS_REGION" \
        --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")
    
    if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
        log_info "Creating security group '$SG_NAME'..."
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SG_NAME" \
            --description "Security group for MR Optimum Mode 2 ECS tasks" \
            --vpc-id "$VPC_ID" \
            $AWS_ARGS --region "$AWS_REGION" \
            --query "GroupId" --output text)
        
        aws ec2 authorize-security-group-egress \
            --group-id "$SG_ID" --protocol -1 --cidr 0.0.0.0/0 \
            $AWS_ARGS --region "$AWS_REGION" 2>/dev/null || true
    fi
fi
log_success "Security Group: $SG_ID"

# ============================================================================
# Step 5: Deploy SAM stack
# ============================================================================
log_step "Step 5: Deploy SAM stack"

# Resolve the CloudMR API host (without protocol or path)
CLOUDMR_HOST=$(echo "$CLOUDMR_API_URL" | sed 's|https\?://||' | sed 's|/.*||')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

# If no explicit S3 bucket provided, generate a deterministic, unique name using the user's email
if [[ -z "${S3_BUCKET:-}" ]]; then
    # Sanitize email to a bucket-friendly token: lowercase, replace @ and invalid chars with '-'
    EMAIL_TOKEN=$(echo "${CLOUDMR_EMAIL,,}" | sed 's/@/-/g; s/[^a-z0-9-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')
    SUFFIX="$(date +%s)-$(printf '%04x' $((RANDOM%65536)))"
    S3_BUCKET="mroptimum-${EMAIL_TOKEN}-${SUFFIX}"
    # Trim to 63 chars (S3 limit)
    if [[ ${#S3_BUCKET} -gt 63 ]]; then
        S3_BUCKET=${S3_BUCKET:0:63}
        S3_BUCKET=$(echo "$S3_BUCKET" | sed 's/-$//')
    fi
    GENERATED_S3_BUCKET=1
else
    GENERATED_S3_BUCKET=0
fi

# Summary before deploying
echo ""
echo -e "  Stack Name:     ${GREEN}$STACK_NAME${NC}"
echo -e "  AWS Profile:    ${GREEN}${AWS_PROFILE:-default}${NC}"
echo -e "  AWS Account:    ${GREEN}$USER_AWS_ACCOUNT_ID${NC}"
echo -e "  AWS Region:     ${GREEN}$AWS_REGION${NC}"
echo -e "  VPC:            ${GREEN}$VPC_ID${NC}"
echo -e "  Subnets:        ${GREEN}$SUBNET_ID_1, $SUBNET_ID_2${NC}"
echo -e "  Security Group: ${GREEN}$SG_ID${NC}"
echo -e "  Lambda Image:   ${GREEN}$LAMBDA_IMAGE_URI${NC}"
echo -e "  Fargate Image:  ${GREEN}$FARGATE_IMAGE_URI${NC}"
echo -e "  CloudMR API:    ${GREEN}$CLOUDMR_API_URL${NC}"
echo -e "  CloudMR User:   ${GREEN}$CLOUDMR_EMAIL${NC}"
echo -e "  Data Bucket:    ${GREEN}$DATA_BUCKET${NC}"
echo -e "  Results Bucket: ${GREEN}$RESULTS_BUCKET${NC}"
echo -e "  Failed Bucket:  ${GREEN}$FAILED_BUCKET${NC}"
echo -e "  S3 Bucket:      ${GREEN}$S3_BUCKET${NC}"
if [[ "$GENERATED_S3_BUCKET" -eq 1 ]]; then
    echo -e "  (auto-generated from email: ${CLOUDMR_EMAIL})"
fi
if [[ -n "$CLOUDMR_ROLE_ARN" ]]; then
    echo -e "  CloudMR Role Arn: ${GREEN}$CLOUDMR_ROLE_ARN${NC}"
fi
if [[ -n "$EXTERNAL_ID" ]]; then
    echo -e "  ExternalId: ${GREEN}$EXTERNAL_ID${NC}"
fi
echo -e "  Mode:           ${GREEN}mode_2 (user-owned)${NC}"
echo ""

read -rp "Proceed with deployment? [Y/n]: " CONFIRM
if [[ "${CONFIRM:-Y}" =~ ^[Nn] ]]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
log_info "Deploying SAM stack (this may take 5-10 minutes)..."

# Mode 2 uses template-mode2.yaml which creates its own S3 buckets
# (Mode 1's template.yaml uses Fn::ImportValue from cloudmr-brain which doesn't exist here)
TEMPLATE_FILE="$ROOT_DIR/template-mode2.yaml"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log_error "Mode 2 template not found: $TEMPLATE_FILE"
    log_info "Ensure template-mode2.yaml exists at the repository root."
    exit 1
fi

log_info "Using Mode 2 template: $TEMPLATE_FILE"

# If an explicit S3 bucket was provided, ensure it exists and is usable by SAM
S3_DEPLOY_ARGS=""
if [[ -n "$S3_BUCKET" ]]; then
    log_info "Using explicit S3 bucket for artifact staging: $S3_BUCKET"

    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$S3_BUCKET" $AWS_ARGS --region "$AWS_REGION" 2>/dev/null; then
        log_warn "S3 bucket '$S3_BUCKET' does not exist. Attempting to create it..."
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket "$S3_BUCKET" $AWS_ARGS --region "$AWS_REGION"
        else
            aws s3api create-bucket --bucket "$S3_BUCKET" --create-bucket-configuration LocationConstraint="$AWS_REGION" $AWS_ARGS --region "$AWS_REGION"
        fi

        # Re-check
        if ! aws s3api head-bucket --bucket "$S3_BUCKET" $AWS_ARGS --region "$AWS_REGION" 2>/dev/null; then
            log_error "Failed to create or access S3 bucket '$S3_BUCKET'. Check permissions and try again."
            exit 1
        fi
        log_success "Created S3 bucket: $S3_BUCKET"
    else
        log_success "S3 bucket exists: $S3_BUCKET"
    fi

    S3_DEPLOY_ARGS="--s3-bucket $S3_BUCKET"
    # When providing an explicit s3 bucket, ensure SAM does not attempt to auto-resolve S3
    S3_RESOLVE_FLAG="--no-resolve-s3"
fi

# Build SAM parameter overrides and only include optional params when provided
PARAM_OVERRIDES=(
    "LambdaImageUri=$LAMBDA_IMAGE_URI"
    "FargateImageUri=$FARGATE_IMAGE_URI"
    "CortexHost=$CLOUDMR_HOST"
    "ECSClusterName=${STACK_NAME}-cluster"
    "SubnetId1=$SUBNET_ID_1"
    "SubnetId2=$SUBNET_ID_2"
    "SecurityGroupIds=$SG_ID"
    "DataBucketName=$DATA_BUCKET"
    "ResultsBucketName=$RESULTS_BUCKET"
    "FailedBucketName=$FAILED_BUCKET"
    "StageName=Prod"
)
# Include CloudMRQueueJobRoleArn only if provided; otherwise leave blank so the
# template will fall back to the CloudMR account root (less secure but avoids
# invalid principal errors when the specific role ARN is not known).
if [[ -n "$CLOUDMR_ROLE_ARN" ]]; then
    PARAM_OVERRIDES+=("CloudMRQueueJobRoleArn=$CLOUDMR_ROLE_ARN")
else
    log_warn "No CloudMR QueueJob role ARN supplied; the stack will default to allowing the CloudMR account root to assume the role. For best security, provide a specific role ARN with --cloudmr-role-arn."
fi
if [[ -n "$EXTERNAL_ID" ]]; then
    PARAM_OVERRIDES+=("ExternalId=$EXTERNAL_ID")
fi
PARAM_OVERRIDES_STR="${PARAM_OVERRIDES[*]}"

sam deploy \
    --template-file "$TEMPLATE_FILE" \
    $AWS_ARGS \
    --region "$AWS_REGION" \
    $S3_DEPLOY_ARGS $S3_RESOLVE_FLAG \
    --stack-name "$STACK_NAME" \
    --parameter-overrides $PARAM_OVERRIDES_STR \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --no-confirm-changeset

# Check deployment status
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    $AWS_ARGS --region "$AWS_REGION" \
    --query 'Stacks[0].StackStatus' --output text)

if [[ "$STACK_STATUS" == *"ROLLBACK"* ]] || [[ "$STACK_STATUS" == *"FAILED"* ]]; then
    log_error "Stack deployment failed! Status: $STACK_STATUS"
    log_info "Check events: aws cloudformation describe-stack-events --stack-name $STACK_NAME $AWS_ARGS --region $AWS_REGION"
    exit 1
fi

log_success "Stack deployed: $STACK_STATUS"

# ============================================================================
# Step 6: Get stack outputs
# ============================================================================
log_step "Step 6: Get stack outputs"

# Show all outputs
aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    $AWS_ARGS --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' --output table

# Extract State Machine ARN (try both output key names)
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    $AWS_ARGS --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CalculationStateMachineArn`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [[ -z "$STATE_MACHINE_ARN" || "$STATE_MACHINE_ARN" == "None" ]]; then
    STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        $AWS_ARGS --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
        --output text 2>/dev/null || echo "")
fi

if [[ -z "$STATE_MACHINE_ARN" || "$STATE_MACHINE_ARN" == "None" ]]; then
    log_error "Could not find State Machine ARN in stack outputs"
    exit 1
fi
log_success "State Machine ARN: $STATE_MACHINE_ARN"

# Try to get the cross-account role ARN (optional)
CROSS_ACCOUNT_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    $AWS_ARGS --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudMRCrossAccountRoleArn`].OutputValue' --output text 2>/dev/null || echo "")

if [[ -n "$CROSS_ACCOUNT_ROLE_ARN" && "$CROSS_ACCOUNT_ROLE_ARN" != "None" ]]; then
    log_success "Cross-account role ARN: $CROSS_ACCOUNT_ROLE_ARN"
else
    log_info "No cross-account role ARN found in stack outputs (this is optional)."
    CROSS_ACCOUNT_ROLE_ARN=""
fi

# Verify the deployed role's trust policy so it explicitly allows the QueueJob role
if [[ -n "$CROSS_ACCOUNT_ROLE_ARN" ]]; then
        ROLE_NAME="${STACK_NAME}-CloudMRCrossAccountRole"
        log_step "Verify cross-account role trust policy ($ROLE_NAME)"
        ASSUME_POLICY_JSON=$(aws iam get-role --role-name "$ROLE_NAME" $AWS_ARGS --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null || echo "")
        if [[ -z "$ASSUME_POLICY_JSON" ]]; then
                log_warn "Could not read assume-role policy for $ROLE_NAME. Skipping trust verification."
        else
                PRINC_AWS=$(echo "$ASSUME_POLICY_JSON" | jq -r '.Statement[]?.Principal?.AWS' | tr '\n' ' ')
                if echo "$PRINC_AWS" | grep -F -q "$CLOUDMR_ROLE_ARN"; then
                        log_success "Role trust policy already grants assume to: $CLOUDMR_ROLE_ARN"
                else
                        log_warn "Role trust policy does NOT grant assume to: $CLOUDMR_ROLE_ARN"
                        echo "Current assume-role policy:"; echo "$ASSUME_POLICY_JSON" | jq .
                        # Decide whether to auto-update (non-interactive) or prompt
                        if [[ "$AUTO_UPDATE_TRUST" == "true" ]]; then
                            # Auto-update requires a provided CloudMR role ARN
                            if [[ -z "$CLOUDMR_ROLE_ARN" ]]; then
                                log_error "--auto-update-trust requires --cloudmr-role-arn to be supplied. Aborting."
                                exit 1
                            fi
                            log_info "Auto-updating trust policy to allow $CLOUDMR_ROLE_ARN to assume $ROLE_NAME (non-interactive)"
                            DO_UPDATE=true
                        else
                            if [[ "$ASSUME_YES" == "true" ]]; then
                                DO_UPDATE=true
                            else
                                read -rp "Update trust policy to allow $CLOUDMR_ROLE_ARN to assume this role now? [Y/n]: " UPDATE_TRUST
                                if [[ "${UPDATE_TRUST:-Y}" =~ ^[Yy] ]]; then
                                    DO_UPDATE=true
                                else
                                    DO_UPDATE=false
                                fi
                            fi
                        fi

                        if [[ "$DO_UPDATE" == "true" ]]; then
                            TMP_TRUST_FILE=$(mktemp /tmp/mroptimum-trust.XXXXXX.json)
                            if [[ -n "$EXTERNAL_ID" ]]; then
                                cat > "$TMP_TRUST_FILE" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": { "AWS": "$CLOUDMR_ROLE_ARN" },
            "Action": "sts:AssumeRole",
            "Condition": { "StringEquals": { "sts:ExternalId": "$EXTERNAL_ID" } }
        }
    ]
}
EOF
                            else
                                cat > "$TMP_TRUST_FILE" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": { "AWS": "$CLOUDMR_ROLE_ARN" },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
                            fi

                            ERROR_FILE=$(mktemp /tmp/mroptimum-trust-err.XXXXXX)
                            if aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document file://"$TMP_TRUST_FILE" $AWS_ARGS 2>"$ERROR_FILE"; then
                                log_success "Updated trust policy for $ROLE_NAME to allow $CLOUDMR_ROLE_ARN"
                                # re-read policy
                                ASSUME_POLICY_JSON=$(aws iam get-role --role-name "$ROLE_NAME" $AWS_ARGS --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null || echo "")
                                echo "New assume-role policy:"; echo "$ASSUME_POLICY_JSON" | jq .
                                TRUST_UPDATED="true"
                                TRUST_UPDATED_AT="$(date --utc +%Y-%m-%dT%H:%M:%SZ)"
                                TRUST_UPDATED_BY="$CLOUDMR_EMAIL"
                                TRUST_UPDATED_AUTOMATIC="${AUTO_UPDATE_TRUST:-false}"
                            else
                                log_error "Failed to update trust policy for $ROLE_NAME. Ensure your AWS credentials have iam:UpdateAssumeRolePolicy permission."
                                log_error "AWS error message:"; sed -n '1,120p' "$ERROR_FILE" || true
                                rm -f "$TMP_TRUST_FILE" "$ERROR_FILE"
                                exit 1
                            fi
                            rm -f "$TMP_TRUST_FILE" "$ERROR_FILE"
                        else
                            log_info "Skipping trust policy update. If you skip, CloudMR will not be able to assume this role until it is updated."
                        fi
                fi
        fi
fi

# Bucket names are known from our parameters (no need to query stack outputs)
# They were already set from defaults or CLI flags
log_success "Data Bucket:    $DATA_BUCKET"
log_success "Results Bucket: $RESULTS_BUCKET"
log_success "Failed Bucket:  $FAILED_BUCKET"

# Write outputs to file
EXPORTS_FILE="exports.mode2.sh"
cat > "$ROOT_DIR/$EXPORTS_FILE" <<EOF
# Auto-generated by scripts/deploy-and-register-mode2.sh
# $(date --utc +%Y-%m-%dT%H:%M:%SZ)
export MODE2_AWS_ACCOUNT_ID="$USER_AWS_ACCOUNT_ID"
export MODE2_AWS_PROFILE="$AWS_PROFILE"
export MODE2_STATE_MACHINE_ARN="$STATE_MACHINE_ARN"
export MODE2_RESULTS_BUCKET="$RESULTS_BUCKET"
export MODE2_FAILED_BUCKET="$FAILED_BUCKET"
export MODE2_DATA_BUCKET="$DATA_BUCKET"
export MODE2_STACK_NAME="$STACK_NAME"
export MODE2_REGION="$AWS_REGION"
export MODE2_CROSS_ACCOUNT_ROLE_ARN="$CROSS_ACCOUNT_ROLE_ARN"
export CROSS_ACCOUNT_ROLE_ARN="$CROSS_ACCOUNT_ROLE_ARN"
EOF
log_success "Wrote $EXPORTS_FILE"

# If we updated the trust policy automatically, record an audit note in the exports file
if [[ "${TRUST_UPDATED:-false}" == "true" ]]; then
    cat >> "$ROOT_DIR/$EXPORTS_FILE" <<EOF
# Cross-account role trust policy was updated by deploy script
export MODE2_CROSS_ACCOUNT_ROLE_TRUST_UPDATED="true"
export MODE2_CROSS_ACCOUNT_ROLE_TRUST_UPDATED_AT="$TRUST_UPDATED_AT"
export MODE2_CROSS_ACCOUNT_ROLE_TRUST_UPDATED_BY="$TRUST_UPDATED_BY"
export MODE2_CROSS_ACCOUNT_ROLE_TRUST_UPDATED_AUTOMATIC="$TRUST_UPDATED_AUTOMATIC"
EOF
    log_info "Wrote trust update audit to $EXPORTS_FILE"
fi

# ============================================================================
# Step 7: Register Mode 2 computing unit with CloudMR Brain
# ============================================================================
log_step "Step 7: Register Mode 2 computing unit"

if [[ -z "$ALIAS" ]]; then
    ALIAS="$ALIAS_DEFAULT"
fi

REG_PAYLOAD=$(jq -n \
    --arg appName "$APP_NAME" \
    --arg mode "mode_2" \
    --arg provider "user" \
    --arg awsAccountId "$USER_AWS_ACCOUNT_ID" \
    --arg region "$AWS_REGION" \
    --arg stateMachineArn "$STATE_MACHINE_ARN" \
    --arg resultsBucket "$RESULTS_BUCKET" \
    --arg failedBucket "$FAILED_BUCKET" \
    --arg dataBucket "$DATA_BUCKET" \
    --arg alias "$ALIAS" \
    --arg crossAccountRoleArn "$CROSS_ACCOUNT_ROLE_ARN" \
    --arg externalId "$EXTERNAL_ID" \
    --arg trustUpdated "${TRUST_UPDATED:-false}" \
    --arg trustUpdatedBy "${TRUST_UPDATED_BY:-}" \
    --arg trustUpdatedAt "${TRUST_UPDATED_AT:-}" \
    --arg trustUpdatedAutomatic "${TRUST_UPDATED_AUTOMATIC:-false}" \
    '{
        appName: $appName,
        mode: $mode,
        provider: $provider,
        awsAccountId: $awsAccountId,
        region: $region,
        stateMachineArn: $stateMachineArn,
        resultsBucket: $resultsBucket,
        failedBucket: $failedBucket,
        dataBucket: $dataBucket,
        alias: $alias,
        crossAccountRoleArn: $crossAccountRoleArn,
        externalId: ($externalId // ""),
        # Trust update metadata if the script updated the role
        autoUpdatedTrust: ($trustUpdated == "true"),
        trustUpdatedBy: ($trustUpdatedBy // null),
        trustUpdatedAt: ($trustUpdatedAt // null),
        trustUpdatedAutomatic: ($trustUpdatedAutomatic == "true"),
        isDefault: false
    }')

echo ""
log_info "Registration payload:"
echo "$REG_PAYLOAD" | jq .
echo ""

REG_RESPONSE=$(curl -s -X POST "${CLOUDMR_API_URL}/api/computing-unit/register" \
    -H "Authorization: Bearer ${ID_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$REG_PAYLOAD")

log_info "Registration response:"
echo "$REG_RESPONSE" | jq . 2>/dev/null || echo "$REG_RESPONSE"

COMPUTING_UNIT_ID=$(echo "$REG_RESPONSE" | jq -r '.computingUnitId // empty')

if [[ -z "$COMPUTING_UNIT_ID" ]]; then
    log_error "Registration failed. See response above."
    # Be more robust in detecting the DynamoDB UpdateExpression failure which mentions overlapping document paths
    ERR_MSG=$(echo "$REG_RESPONSE" | jq -r '.error // .message // empty')
    log_info "Server error: $ERR_MSG"
    if [[ "$ERR_MSG" =~ "ValidationException" ]] || [[ "$ERR_MSG" =~ "Invalid UpdateExpression" ]] || [[ "$ERR_MSG" =~ "Two document" ]] || [[ "$ERR_MSG" =~ "crossAccountRoleArn" ]] || [[ "$ERR_MSG" =~ "crossAccountRoleVerified" ]]; then
        log_warn "Detected server-side DynamoDB update error related to crossAccountRoleArn. Retrying registration without cross-account fields..."
        REG_PAYLOAD_NO_ROLE=$(jq 'del(.crossAccountRoleArn) | del(.externalId)' <<< "$REG_PAYLOAD")
        echo "Retry payload:"; echo "$REG_PAYLOAD_NO_ROLE" | jq .
        REG_RESPONSE_2=$(curl -s -X POST "${CLOUDMR_API_URL}/api/computing-unit/register" \
            -H "Authorization: Bearer ${ID_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$REG_PAYLOAD_NO_ROLE")
        echo "Retry response:"; echo "$REG_RESPONSE_2" | jq . 2>/dev/null || echo "$REG_RESPONSE_2"
        COMPUTING_UNIT_ID=$(echo "$REG_RESPONSE_2" | jq -r '.computingUnitId // empty')
        if [[ -n "$COMPUTING_UNIT_ID" ]]; then
            log_success "Registration succeeded without crossAccountRoleArn (role not attached)."
            log_info "The server appears to reject adding the cross-account role due to a DynamoDB UpdateExpression bug."
            log_info "You can attach the cross-account role later by running:"
            log_info "  MODE=mode_2 CROSS_ACCOUNT_ROLE_ARN=$CROSS_ACCOUNT_ROLE_ARN EXTERNAL_ID=$EXTERNAL_ID ./scripts/register-computing-unit.sh"
            log_info "If attaching the role fails similarly, please contact CloudMR support to fix the server-side UpdateExpression (overlapping document paths)."
        else
            log_error "Retry registration also failed. See responses above."
        fi
    fi
    log_info "You can retry registration manually:"
    log_info "  MODE=mode_2 STACK_NAME=$STACK_NAME CLOUDMR_EMAIL=$CLOUDMR_EMAIL CLOUDMR_API_URL=$CLOUDMR_API_URL ./scripts/register-computing-unit.sh"
    exit 1
fi

log_success "Computing unit registered: $COMPUTING_UNIT_ID"

# ============================================================================
# Step 8: Verify — list all computing units
# ============================================================================
log_step "Step 8: Verify registration"

LIST_RESPONSE=$(curl -s -G -H "Authorization: Bearer ${ID_TOKEN}" \
    "${CLOUDMR_API_URL}/api/computing-unit/list" \
    --data-urlencode "app_name=$APP_NAME")

echo ""
log_info "All computing units for '$APP_NAME':"
echo "$LIST_RESPONSE" | jq . 2>/dev/null || echo "$LIST_RESPONSE"

# ============================================================================
# Done
# ============================================================================
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Mode 2 Deploy & Register Complete!                  ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Computing Unit ID:  ${GREEN}$COMPUTING_UNIT_ID${NC}"
echo -e "  Mode:               ${GREEN}mode_2 (User-Owned)${NC}"
echo -e "  AWS Account:        ${GREEN}$USER_AWS_ACCOUNT_ID${NC}"
echo -e "  AWS Profile:        ${GREEN}${AWS_PROFILE:-default}${NC}"
echo -e "  State Machine:      ${GREEN}$STATE_MACHINE_ARN${NC}"
echo -e "  Results Bucket:     ${GREEN}$RESULTS_BUCKET${NC}"
echo -e "  Exports File:       ${GREEN}$EXPORTS_FILE${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Submit a job via CloudMR Brain and select Mode 2"
echo "  2. Monitor costs in AWS Cost Explorer"
echo "  3. To load outputs: source $EXPORTS_FILE"
echo ""
echo -e "${YELLOW}Cleanup:${NC}"
echo "  aws cloudformation delete-stack --stack-name $STACK_NAME $AWS_ARGS --region $AWS_REGION"
echo ""
