#!/bin/bash

# Variables
STACK_NAME="cmr-calculation00"
TEMPLATE_FILE="template.yaml"
SUBNET1_NAME="cmr-calculation00-public-subnet-1"
SUBNET2_NAME="cmr-calculation00-public-subnet-2"

# Function to check if subnets exist
check_subnets_exist() {
    echo "Checking if subnets already exist..."
    
    # Check for Subnet 1
    SUBNET1_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$SUBNET1_NAME" --query "Subnets[0].SubnetId" --output text)
    
    # Check for Subnet 2
    SUBNET2_ID=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$SUBNET2_NAME" --query "Subnets[0].SubnetId" --output text)
    
    if [ "$SUBNET1_ID" != "None" ] && [ "$SUBNET2_ID" != "None" ]; then
        echo "Subnets already exist:"
        echo "Subnet 1 ID: $SUBNET1_ID"
        echo "Subnet 2 ID: $SUBNET2_ID"
        return 0  # Subnets exist
    else
        echo "Subnets do not exist."
        return 1  # Subnets do not exist
    fi
}

# Main script logic
if check_subnets_exist; then
    echo "Subnets are already available. Skipping VPC deployment."
else
    echo "Subnets are not available. Building and deploying the VPC stack..."
    
    # Build the SAM template
    sam build --template-file $TEMPLATE_FILE
    
    # Deploy the SAM template
    sam deploy \
        --stack-name $STACK_NAME \
        --capabilities CAPABILITY_IAM \
        --no-fail-on-empty-changeset
fi