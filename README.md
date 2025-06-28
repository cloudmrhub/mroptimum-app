# MR-Optimum Backend

This document describes how we build and deploy the MR-Optimum backend. You’ll see how our shell script (`setup.sh`) discovers networking and container-image parameters, how SAM templates wire everything together, and what the final AWS architecture looks like.

---

## 1. High-Level Architecture

At the top level we have one CloudFormation/SAM stack that nests two Serverless applications:

  • **ArkApp**  
    - Creates two S3 buckets:  
      1. `ResultsBucket` for successful output ZIPs  
      2. `FailedBucket` for failure ZIPs  
    - Exports their names via CloudFormation Outputs for cross-stack use.

  • **CalculationApp**  
    - Builds and deploys two container images to ECR:  
      - A **Lambda** container (light tasks)  
      - A **Fargate** container (heavy compute)  
    - Provisions an ECS cluster, IAM roles, EventBridge rules, and networking.  
    - Defines a Step Functions State Machine that dynamically chooses:  
      1. Invoke the Lambda image  
      2. Run the Fargate task in awsvpc mode

Clients only need the exported State Machine ARN to start jobs.

---

## 2. Variables & AWS Resources

These variables are initialized in `setup.sh` and then passed into SAM:

  • **AWS_REGION / ACCOUNT_ID**  
    Used to build ARNs and select resources.  

  • **LAMBDA_REPO / FARGATE_REPO**  
    Names of the ECR repositories where we push our Docker images.  

  • **LAMBDA_IMAGE_URI / FARGATE_IMAGE_URI**  
    Fully qualified ECR URIs (`<account>.dkr.ecr.<region>.amazonaws.com/<repo>:latest`).

  • **VPC / SubnetId1 / SubnetId2**  
    `setup.sh` discovers your default VPC, finds two public subnets (one per AZ) for Fargate.  

  • **SecurityGroupIds**  
    The default security group of the VPC, used by Fargate awsvpc tasks.  

  • **ECSClusterName**  
    Name of the ECS cluster (created if missing).  

  • **StateMachineInvokeRole**  
    IAM Role that Step Functions assumes. It must allow:  
      - `lambda:InvokeFunction`  
      - `ecs:RunTask` + `iam:PassRole`  
      - EventBridge calls (`events:PutRule`, `DescribeRule`, `PutTargets`, etc.)

---

## 3. Setup Script (`setup.sh`) – Narrative

1. **Initialize AWS Context**  
   - Hard-code `AWS_REGION="us-east-1"`.  
   - Fetch `ACCOUNT_ID` via `aws sts get-caller-identity --profile nyu`.

2. **Ensure ECR Repositories Exist**  
   For each of `mroptimum-run-job-lambda` and `mroptimum-run-job-fargate`:  
   - Describe the repo; if missing, create it.  

3. **Attempt Service-Linked Role**  
   We run:
   ```bash
   aws iam create-service-linked-role \
     --aws-service-name states.amazonaws.com \
     --description "Step Functions EventBridge SL role" \
     --profile nyu
   ```
   If AccessDenied, we catch and ignore it—our custom role will carry the necessary EventBridge permissions.

4. **Authenticate Docker to ECR**  
   ```bash
   aws ecr get-login-password --region $AWS_REGION --profile nyu \
     | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
   ```

5. **Build & Push Container Images**  
   ```bash
   cd backend/calculation/src

   # Fargate image
   docker build --target fargate-image -t $FARGATE_REPO:latest .
   docker tag  $FARGATE_REPO:latest $FARGATE_IMAGE_URI
   docker push $FARGATE_IMAGE_URI

   # Lambda image
   docker build --target lambda-image -t $LAMBDA_REPO:latest .
   docker tag  $LAMBDA_REPO:latest $LAMBDA_IMAGE_URI
   docker push $LAMBDA_IMAGE_URI
   ```

6. **Discover Networking**  
   - `VPC=$(aws ec2 describe-vpcs …)`  
   - Query public subnets, pick one per AZ → `SUBNETS=$Subnet1,$Subnet2`  
   - Lookup default security group → `SECURITY_GROUP`

7. **Trigger SAM Build & Deploy**  
   ```bash
   cd $ROOT/backend

   sam build --use-container --profile nyu
   sam deploy \
     --stack-name mroptimum-app-test \
     --profile nyu \
     --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
     --resolve-image-repos --resolve-s3 \
     --parameter-overrides \
       CortexHost=<your-API> \
       FargateImageUri=$FARGATE_IMAGE_URI \
       LambdaImageUri=$LAMBDA_IMAGE_URI \
       ECSClusterName=run-job-cluster \
       SubnetId1=$SUBNET1 SubnetId2=$SUBNET2 \
       SecurityGroupIds=$SECURITY_GROUP \
     --region $AWS_REGION
   ```

---

## 4. How It All Fits Together

1. **`setup.sh`** discovers your AWS context (account, subnets, SG) and pushes two Docker images to ECR.  
2. **Parent `template.yaml`** defines parameters (buckets, image URIs, networking, stage name) and nests two applications:  
   - `ArkApp` → produces S3 buckets  
   - `CalculationApp` → consumes those buckets and the image URIs  
3. **`CalculationApp/template.yaml`**:  
   - Creates `StateMachineInvokeRole` with Lambda/ECS/EventBridge permissions  
   - Defines a Step Functions State Machine (`JobChooserStateMachine` + `RunFargateStep`) that uses that role  
   - Provisions ECS cluster and Fargate task roles  
4. **Runtime Flow**:  
   - A client invokes the State Machine ARN → Step Functions evaluates `task["name"]` → either:  
     • `LambdaInvoke` (calls the Lambda container)  
     • `RunFargateStep` (runs the container on Fargate in your VPC)  
   - Each branch writes outputs to the S3 buckets managed by `ArkApp`.

---

## 5. Architecture Diagram

                                                    ┌─────────────┐
                                              ┌────▶│ Results S3  │
                                              │     └─────────────┘
   Client ──▶ API Gateway ──▶ Step Functions ─┤     ┌─────────────┐
                                              └────▶│ Failed S3   │
                                                    └─────────────┘

Step Functions branches into:
• **Lambda** (container image)  
• **Fargate** (same image, awsvpc mode across two public subnets)

---

*Dr. Eros Montin, PhD*  
http://me.biodimensional.com  
**46&2 just ahead of me!**