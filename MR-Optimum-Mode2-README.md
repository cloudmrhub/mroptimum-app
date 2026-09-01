# MR Optimum Mode 2 — Setup and Teardown

This guide explains how a new CloudMRHub user can deploy an MR Optimum **Mode 2** worker in their own AWS account.

Mode 2 creates an API Gateway endpoint, a dispatcher Lambda, and on-demand Fargate compute in the user's AWS account. The Fargate task runs only when a job is submitted. Docker is not required locally because the deployment uses the public MR Optimum container image.

## 1. Requirements

### All operating systems

- A working CloudMRHub email and password
- An AWS account
- A dedicated AWS IAM user with Mode 2 deployment permissions
- Git
- Python 3.9 or newer
- AWS CLI v2
- Internet access
- An AWS VPC with a subnet that provides outbound internet access

### Windows

- Windows 10 or 11
- PowerShell
- Python available through `py` or `python`

### macOS

- Terminal
- Python available through `python3`
- Git and AWS CLI v2

### Linux

- A shell such as Bash
- Python 3 with `venv` and `pip`
- Git and AWS CLI v2

## 2. Credentials: what each one is for

| Credential | Used where | Save it? |
|---|---|---|
| CloudMRHub email | Deployment command and CloudMRHub login | Yes |
| CloudMRHub password | Hidden deployment/teardown prompt | Use a password manager; never put it in the command |
| AWS console username/password | AWS website only | Store securely |
| AWS Access Key ID | AWS CLI profile | Save securely |
| AWS Secret Access Key | AWS CLI profile | Save securely; AWS shows it only once |
| Worker API key | Generated automatically | Saved by the manager; do not share it |

AWS console credentials and AWS CLI access keys are separate. Creating a console password does not create an Access Key ID.

## 3. Create the AWS IAM user

An AWS administrator should:

1. Open **AWS Console → IAM → Users → Create user**.
2. Create a dedicated user such as `mroptimum-mode2-user`.
3. Enable console access only if the user needs the AWS website.
4. Assign the permissions required to deploy Mode 2.

The deployment user must be able to:

- call `sts:GetCallerIdentity`;
- discover VPCs and subnets with EC2 `Describe*` operations;
- create, update, inspect, and delete CloudFormation stacks;
- create the stack's IAM roles and policies and call `iam:PassRole`;
- provision Lambda, API Gateway, ECS/Fargate, EC2 security groups, S3, CloudWatch Logs, and EventBridge resources.

The current repository does not contain a tested least-privilege deployer policy. Use a dedicated, administrator-approved deployment policy. Never use AWS root credentials.

## 4. Create the Access Key ID and Secret Access Key

1. Open **AWS Console → IAM → Users**.
2. Select the Mode 2 user.
3. Open **Security credentials**.
4. Under **Access keys**, select **Create access key**.
5. Choose **Command Line Interface (CLI)**.
6. Complete the acknowledgement.
7. Create the key and download the CSV.

The secret access key is displayed only once. Do not send the CSV through email or chat, and never commit it to GitHub.

## 5. Create the AWS CLI profile

Run this on Windows, macOS, or Linux:

```bash
aws configure --profile mroptimum
```

Enter:

```text
AWS Access Key ID: <ACCESS_KEY_ID>
AWS Secret Access Key: <SECRET_ACCESS_KEY>
Default region name: us-east-1
Default output format: json
```

Verify the identity:

```bash
aws sts get-caller-identity --profile mroptimum
```

Confirm that the returned account and IAM user are correct before continuing.

AWS normally saves the profile in:

- Windows: `%USERPROFILE%\.aws\credentials`
- macOS/Linux: `~/.aws/credentials`

## 6. Install MR Optimum

### Windows PowerShell

```powershell
git clone https://github.com/cloudmrhub/mroptimum-app.git
Set-Location mroptimum-app
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install boto3 requests
```

### macOS

```bash
git clone https://github.com/cloudmrhub/mroptimum-app.git
cd mroptimum-app
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install boto3 requests
```

### Linux

```bash
git clone https://github.com/cloudmrhub/mroptimum-app.git
cd mroptimum-app
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install boto3 requests
```

If `venv` is missing on Ubuntu/Debian:

```bash
sudo apt install python3-venv
```

## 7. Deploy Mode 2

Replace the placeholders with the user's CloudMRHub email and a recognizable worker name.

### Windows

```powershell
python -X utf8 worker/manage.py deploy --profile mroptimum --email <CLOUDMR_EMAIL> --alias "<WORKER_NAME>"
```

Windows uses `-X utf8` to prevent a `UnicodeDecodeError` while the current manager reads its CloudFormation template.

### macOS or Linux

```bash
python worker/manage.py deploy --profile mroptimum --email <CLOUDMR_EMAIL> --alias "<WORKER_NAME>"
```

The manager asks:

```text
AWS region [us-east-1]:
CloudMR password:
```

Press Enter to accept `us-east-1`, then enter the user's existing **CloudMRHub password**. Do not enter the AWS console password or AWS Secret Access Key here.

The manager:

1. logs in to CloudMRHub;
2. reads AWS credentials from the `mroptimum` profile;
3. verifies the AWS account;
4. detects the VPC and subnets;
5. deploys the `mroptimum-worker-mode2` stack; and
6. registers the generated worker with CloudMRHub.

## 8. Verify and use Mode 2

Windows:

```powershell
python -X utf8 worker/manage.py status --profile mroptimum
```

macOS/Linux:

```bash
python worker/manage.py status --profile mroptimum
```

A working deployment reports:

- `CREATE_COMPLETE`
- an API Gateway endpoint
- `Health: OK`

Sign in to MR Optimum with the same CloudMRHub account. Submit a job and select the new worker alias from the computing-unit list.

## 9. Update or inspect the worker

Add `-X utf8` after `python` on Windows.

```bash
python worker/manage.py logs --profile mroptimum --follow
python worker/manage.py costs --profile mroptimum
python worker/manage.py update --profile mroptimum
```

## 10. Tear down Mode 2

Use the manager instead of deleting the stack directly in AWS. The manager first removes the worker from CloudMRHub and then deletes the AWS resources.

Windows:

```powershell
python -X utf8 worker/manage.py teardown
```

macOS/Linux:

```bash
python worker/manage.py teardown
```

Confirm with `y` and enter the CloudMRHub password when prompted.

A successful teardown reports:

```text
Deregistered: <WORKER_NAME> (...)
✓ Stack deleted. All costs stopped.
```

The computing-unit list updates when the web application fetches it again. Refresh the MR Optimum page. If deregistration reports a warning, the AWS stack may be deleted while the old worker remains visible and requires manual removal.

## 11. What to keep and remember

- Remember the AWS profile name: `mroptimum`.
- Keep the CloudMRHub email and password in a password manager.
- Protect the AWS access-key CSV and `~/.aws/credentials`.
- Protect `~/.mroptimum/config.toml`; it contains the generated worker API key.
- Never commit credentials, passwords, tokens, account configuration, or `.mroptimum/config.toml` to GitHub.
- Rotate or delete unused IAM access keys.
- Always use `worker/manage.py teardown` so AWS deletion and CloudMRHub deregistration happen together.

## Troubleshooting

- **Access key age is blank:** create an access key under the IAM user's **Security credentials**.
- **Unable to locate credentials:** run `aws configure --profile mroptimum`.
- **Wrong AWS account:** run `aws sts get-caller-identity --profile mroptimum`.
- **CloudMR login failed:** verify the same credentials in the CloudMRHub web application.
- **AccessDenied / InsufficientCapabilities:** the IAM user lacks a required deployment permission.
- **UnicodeDecodeError on Windows:** run the manager with `python -X utf8`.
- **No suitable subnet:** provide a VPC subnet with outbound internet access.
- **Worker remains visible after teardown:** check whether the output reported successful deregistration, then refresh the web application.

## Sources

- [MR Optimum Mode 2 worker](https://github.com/cloudmrhub/mroptimum-app/tree/main/worker)
- [AWS CLI named profiles](https://docs.aws.amazon.com/cli/latest/reference/configure/)
- [AWS IAM-user CLI credentials](https://docs.aws.amazon.com/cli/v1/userguide/cli-authentication-user.html)
