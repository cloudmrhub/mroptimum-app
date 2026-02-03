#!/bin/bash
#
# MR Optimum Mode 2 Deployment Script
# 
# This script deploys MR Optimum compute infrastructure to YOUR AWS account.
# No Docker build required - images are pulled from CloudMRHub's public ECR.
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Your CloudMR user token (from your profile page at cloudmrhub.com)
#
# Usage:
#   ./deploy-mode2.sh
#   ./deploy-mode2.sh --stack-name my-custom-name --region us-west-2
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
STACK_NAME="mroptimum-mode2"
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
CLOUDMR_API_URL="https://api.cloudmrhub.com"
IMAGE_TAG="latest"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --api-url)
            CLOUDMR_API_URL="$2"
            shift 2
            ;;
        --image-tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --stack-name NAME    CloudFormation stack name (default: mroptimum-mode2)"
            echo "  --region REGION      AWS region (default: us-east-1)"
            echo "  --api-url URL        CloudMR API URL (default: https://api.cloudmrhub.com)"
            echo "  --image-tag TAG      Docker image tag (default: latest)"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       MR Optimum Mode 2 - User-Owned Deployment               ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed.${NC}"
    echo "Please install AWS CLI: https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: AWS credentials not configured.${NC}"
    echo "Please run 'aws configure' or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
    exit 1
fi
echo -e "${GREEN}✓ AWS Account: $AWS_ACCOUNT_ID${NC}"

# Get CloudMR User Token
echo ""
echo -e "${YELLOW}Please enter your CloudMR credentials:${NC}"
echo "You can find your token at: https://cloudmrhub.com/profile"
echo ""
read -sp "CloudMR User Token: " CLOUDMR_USER_TOKEN
echo ""

if [ -z "$CLOUDMR_USER_TOKEN" ]; then
    echo -e "${RED}Error: CloudMR token is required.${NC}"
    exit 1
fi

# Validate token (optional - try to fetch profile)
echo -e "${YELLOW}Validating CloudMR token...${NC}"
PROFILE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $CLOUDMR_USER_TOKEN" \
    "$CLOUDMR_API_URL/api/auth/profile" 2>/dev/null || echo "000")

if [ "$PROFILE_RESPONSE" != "200" ]; then
    echo -e "${RED}Error: Invalid CloudMR token (HTTP $PROFILE_RESPONSE).${NC}"
    echo "Please check your token and try again."
    exit 1
fi
echo -e "${GREEN}✓ CloudMR token validated${NC}"

# Get VPC information
echo ""
echo -e "${YELLOW}Fetching VPC information...${NC}"
DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" \
    --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION" 2>/dev/null || echo "None")

if [ "$DEFAULT_VPC" = "None" ] || [ -z "$DEFAULT_VPC" ]; then
    echo -e "${YELLOW}No default VPC found. Available VPCs:${NC}"
    aws ec2 describe-vpcs --query "Vpcs[*].[VpcId,Tags[?Key=='Name'].Value|[0]]" \
        --output table --region "$AWS_REGION"
    read -p "Enter VPC ID: " VPC_ID
else
    echo -e "${GREEN}Found default VPC: $DEFAULT_VPC${NC}"
    read -p "Use default VPC? [Y/n]: " USE_DEFAULT
    if [[ "$USE_DEFAULT" =~ ^[Nn] ]]; then
        aws ec2 describe-vpcs --query "Vpcs[*].[VpcId,Tags[?Key=='Name'].Value|[0]]" \
            --output table --region "$AWS_REGION"
        read -p "Enter VPC ID: " VPC_ID
    else
        VPC_ID=$DEFAULT_VPC
    fi
fi

# Get subnets
echo ""
echo -e "${YELLOW}Fetching public subnets...${NC}"
SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
    --query "Subnets[*].[SubnetId,AvailabilityZone]" \
    --output text --region "$AWS_REGION")

if [ -z "$SUBNETS" ]; then
    echo -e "${YELLOW}No public subnets found. Available subnets:${NC}"
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]" \
        --output table --region "$AWS_REGION"
    read -p "Enter first subnet ID: " SUBNET_ID_1
    read -p "Enter second subnet ID: " SUBNET_ID_2
else
    SUBNET_ID_1=$(echo "$SUBNETS" | head -n1 | awk '{print $1}')
    SUBNET_ID_2=$(echo "$SUBNETS" | sed -n '2p' | awk '{print $1}')
    
    if [ -z "$SUBNET_ID_2" ]; then
        SUBNET_ID_2=$SUBNET_ID_1
        echo -e "${YELLOW}Warning: Only one public subnet found. Using same subnet for both.${NC}"
    fi
    
    echo -e "${GREEN}✓ Subnet 1: $SUBNET_ID_1${NC}"
    echo -e "${GREEN}✓ Subnet 2: $SUBNET_ID_2${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Deployment Summary:${NC}"
echo -e "  Stack Name:     ${GREEN}$STACK_NAME${NC}"
echo -e "  AWS Region:     ${GREEN}$AWS_REGION${NC}"
echo -e "  AWS Account:    ${GREEN}$AWS_ACCOUNT_ID${NC}"
echo -e "  VPC:            ${GREEN}$VPC_ID${NC}"
echo -e "  Subnets:        ${GREEN}$SUBNET_ID_1, $SUBNET_ID_2${NC}"
echo -e "  Image Tag:      ${GREEN}$IMAGE_TAG${NC}"
echo -e "  CloudMR API:    ${GREEN}$CLOUDMR_API_URL${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

read -p "Proceed with deployment? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Deploy CloudFormation stack
echo ""
echo -e "${YELLOW}Deploying CloudFormation stack...${NC}"
echo "This may take 5-10 minutes..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/template-mode2.yaml"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}Error: Template file not found: $TEMPLATE_FILE${NC}"
    exit 1
fi

aws cloudformation deploy \
    --template-file "$TEMPLATE_FILE" \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --parameter-overrides \
        CloudMRApiUrl="$CLOUDMR_API_URL" \
        CloudMRUserToken="$CLOUDMR_USER_TOKEN" \
        VpcId="$VPC_ID" \
        SubnetId1="$SUBNET_ID_1" \
        SubnetId2="$SUBNET_ID_2" \
        ImageTag="$IMAGE_TAG" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --no-fail-on-empty-changeset

# Check deployment status
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].StackStatus" \
    --output text --region "$AWS_REGION")

if [[ "$STACK_STATUS" == *"COMPLETE"* ]] && [[ "$STACK_STATUS" != *"ROLLBACK"* ]]; then
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Deployment Successful!                              ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get outputs
    echo -e "${BLUE}Stack Outputs:${NC}"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
        --output table --region "$AWS_REGION"
    
    echo ""
    echo -e "${GREEN}Your Mode 2 computing unit has been automatically registered with CloudMR Brain.${NC}"
    echo -e "${GREEN}You can now select 'Mode 2 - User Owned' in the MR Optimum web interface.${NC}"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "  • Compute costs will be charged to YOUR AWS account"
    echo "  • Results are stored in YOUR S3 buckets"
    echo "  • To delete, run: aws cloudformation delete-stack --stack-name $STACK_NAME"
    
else
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║           Deployment Failed!                                  ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Stack status: $STACK_STATUS"
    echo ""
    echo "To see error details, run:"
    echo "  aws cloudformation describe-stack-events --stack-name $STACK_NAME --region $AWS_REGION"
    exit 1
fi
