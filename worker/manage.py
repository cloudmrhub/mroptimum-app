#!/usr/bin/env python3
"""
MR Optimum Mode 2 — Worker Manager

A simple Python tool for users to deploy, monitor, and teardown their
Mode 2 computing unit on AWS. No knowledge of CloudFormation required.

Usage:
    python manage.py deploy     — Deploy the worker stack
    python manage.py status     — Check worker health + running tasks
    python manage.py logs       — Tail recent computation logs
    python manage.py costs      — Show estimated costs (recent tasks)
    python manage.py teardown   — Delete the stack (stop all costs)

Requirements:
    pip install boto3 requests
    AWS CLI configured (aws configure --profile <your-profile>)
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

try:
    import boto3
    import requests
except ImportError:
    print("Missing dependencies. Run: pip install boto3 requests")
    sys.exit(1)


# ═══════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════
STACK_NAME = "mroptimum-worker-mode2"
TEMPLATE_PATH = Path(__file__).parent / "deploy" / "template.yaml"
BRAIN_API_URL = "https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod"
ECR_IMAGE = "469266894233.dkr.ecr.us-east-1.amazonaws.com/mroptimum-fargate:latest"
DEFAULT_REGION = "us-east-1"


# ═══════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════
def color(text, c):
    colors = {"green": "\033[92m", "red": "\033[91m", "yellow": "\033[93m", "blue": "\033[94m", "bold": "\033[1m", "end": "\033[0m"}
    return f"{colors.get(c, '')}{text}{colors['end']}"


def get_session(profile=None, region=None):
    return boto3.Session(profile_name=profile, region_name=region or DEFAULT_REGION)


def get_stack_outputs(session, stack_name=STACK_NAME):
    cf = session.client("cloudformation")
    try:
        resp = cf.describe_stacks(StackName=stack_name)
        stack = resp["Stacks"][0]
        outputs = {o["OutputKey"]: o["OutputValue"] for o in stack.get("Outputs", [])}
        return stack["StackStatus"], outputs
    except Exception:
        return None, {}


def brain_login(email, password):
    resp = requests.post(f"{BRAIN_API_URL}/api/auth/login", json={"email": email, "password": password})
    data = resp.json()
    if not data.get("success"):
        print(color(f"Login failed: {data.get('message', 'Unknown error')}", "red"))
        sys.exit(1)
    return data


def prompt(text, default=None, secret=False):
    suffix = f" [{default}]" if default else ""
    if secret:
        import getpass
        val = getpass.getpass(f"{text}{suffix}: ")
    else:
        val = input(f"{text}{suffix}: ")
    return val.strip() or default


# ═══════════════════════════════════════════════════════════════
# Commands
# ═══════════════════════════════════════════════════════════════

def cmd_deploy(args):
    """Deploy the Mode 2 worker stack to AWS."""
    print(color("\n╔═══════════════════════════════════════════════╗", "blue"))
    print(color("║  MR Optimum Mode 2 — Deploy Worker            ║", "blue"))
    print(color("╚═══════════════════════════════════════════════╝\n", "blue"))

    # Gather info
    profile = args.profile or prompt("AWS CLI profile", os.environ.get("AWS_PROFILE", "default"))
    region = args.region or prompt("AWS region", DEFAULT_REGION)
    email = args.email or prompt("CloudMR email")
    password = args.password or prompt("CloudMR password", secret=True)
    api_key = args.api_key or prompt("Choose an API key for your worker (any secret string)",
                                     f"mroptimum-{email.split('@')[0]}-2026")

    # Login to Brain
    print(f"\n{color('[1/5]', 'bold')} Logging in to CloudMR Brain...")
    auth = brain_login(email, password)
    token = auth["id_token"]
    user_id = auth["user_id"]
    print(color(f"  Logged in as {email} (user: {user_id})", "green"))

    # Check AWS credentials
    print(f"\n{color('[2/5]', 'bold')} Checking AWS credentials...")
    session = get_session(profile, region)
    sts = session.client("sts")
    identity = sts.get_caller_identity()
    account_id = identity["Account"]
    print(color(f"  AWS Account: {account_id} ({profile})", "green"))

    # Detect networking
    print(f"\n{color('[3/5]', 'bold')} Detecting VPC and subnets...")
    ec2 = session.client("ec2")
    vpcs = ec2.describe_vpcs(Filters=[{"Name": "is-default", "Values": ["true"]}])["Vpcs"]
    if not vpcs:
        vpcs = ec2.describe_vpcs()["Vpcs"]
    vpc_id = vpcs[0]["VpcId"]

    subnets = ec2.describe_subnets(
        Filters=[{"Name": "vpc-id", "Values": [vpc_id]}, {"Name": "map-public-ip-on-launch", "Values": ["true"]}]
    )["Subnets"]
    if len(subnets) < 2:
        subnets = ec2.describe_subnets(Filters=[{"Name": "vpc-id", "Values": [vpc_id]}])["Subnets"]

    subnet1 = subnets[0]["SubnetId"]
    subnet2 = subnets[1]["SubnetId"] if len(subnets) > 1 else subnet1
    print(color(f"  VPC: {vpc_id}", "green"))
    print(color(f"  Subnets: {subnet1}, {subnet2}", "green"))

    # Deploy stack
    print(f"\n{color('[4/5]', 'bold')} Deploying CloudFormation stack...")
    print(f"  Stack: {STACK_NAME}")
    print(f"  This takes 2-3 minutes...\n")

    cf = session.client("cloudformation")
    with open(TEMPLATE_PATH) as f:
        template_body = f.read()

    params = [
        {"ParameterKey": "VpcId", "ParameterValue": vpc_id},
        {"ParameterKey": "SubnetId1", "ParameterValue": subnet1},
        {"ParameterKey": "SubnetId2", "ParameterValue": subnet2},
        {"ParameterKey": "WorkerApiKey", "ParameterValue": api_key},
        {"ParameterKey": "WorkerImageUri", "ParameterValue": ECR_IMAGE},
        {"ParameterKey": "BrainApiUrl", "ParameterValue": BRAIN_API_URL},
        {"ParameterKey": "BrainToken", "ParameterValue": token},
    ]

    try:
        cf.create_stack(
            StackName=STACK_NAME,
            TemplateBody=template_body,
            Parameters=params,
            Capabilities=["CAPABILITY_IAM"],
        )
    except cf.exceptions.AlreadyExistsException:
        cf.update_stack(
            StackName=STACK_NAME,
            TemplateBody=template_body,
            Parameters=params,
            Capabilities=["CAPABILITY_IAM"],
        )

    # Wait for completion
    waiter = cf.get_waiter("stack_create_complete")
    try:
        waiter.wait(StackName=STACK_NAME, WaiterConfig={"Delay": 10, "MaxAttempts": 30})
    except Exception:
        # Maybe it's an update
        try:
            waiter = cf.get_waiter("stack_update_complete")
            waiter.wait(StackName=STACK_NAME, WaiterConfig={"Delay": 10, "MaxAttempts": 30})
        except Exception as e:
            print(color(f"  Deploy failed: {e}", "red"))
            sys.exit(1)

    status, outputs = get_stack_outputs(session)
    endpoint = outputs.get("WorkerEndpoint", "")
    print(color(f"  Stack deployed: {status}", "green"))
    print(color(f"  Endpoint: {endpoint}", "green"))

    # Register with Brain
    print(f"\n{color('[5/5]', 'bold')} Registering with CloudMR Brain...")
    payload = {
        "appName": "MR Optimum",
        "mode": "mode_2",
        "provider": "self-hosted",
        "apiEndpoint": endpoint,
        "apiKey": api_key,
        "alias": args.alias or f"Cloud Worker ({profile})",
        "awsAccountId": account_id,
        "region": region,
        "resultsBucket": "cloudmr-results-cloudmrhub-brain-us-east-1",
        "failedBucket": "cloudmr-failed-cloudmrhub-brain-us-east-1",
        "dataBucket": "cloudmr-data-cloudmrhub-brain-us-east-1",
    }
    resp = requests.post(
        f"{BRAIN_API_URL}/api/computing-unit/register",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
    )
    reg = resp.json()
    print(color(f"  Registered: {reg.get('alias')} (ID: {reg.get('computingUnitId')})", "green"))

    print(color("\n✓ Done! Your Mode 2 worker is ready.", "green"))
    print(f"  Submit jobs from the CloudMR web app selecting your worker.")
    print(f"  Run '{sys.argv[0]} status' to check health.")
    print(f"  Run '{sys.argv[0]} teardown' to delete and stop all costs.\n")


def cmd_status(args):
    """Check worker health and running tasks."""
    print(color("\n  Worker Status\n", "bold"))

    profile = args.profile or os.environ.get("AWS_PROFILE", "default")
    region = args.region or DEFAULT_REGION
    session = get_session(profile, region)

    status, outputs = get_stack_outputs(session)
    if not status:
        print(color("  Stack not found. Run 'deploy' first.", "red"))
        return

    print(f"  Stack:    {STACK_NAME}")
    print(f"  Status:   {color(status, 'green' if 'COMPLETE' in status else 'yellow')}")

    endpoint = outputs.get("WorkerEndpoint", "")
    if endpoint:
        print(f"  Endpoint: {endpoint}")
        try:
            resp = requests.get(f"{endpoint}/health", timeout=10)
            health = resp.json()
            print(f"  Health:   {color('OK', 'green')}")
            print(f"  Type:     {health.get('type', 'unknown')}")
            print(f"  Cluster:  {health.get('cluster', 'N/A')}")
        except Exception as e:
            print(f"  Health:   {color(f'UNREACHABLE ({e})', 'red')}")

    # Check running tasks
    ecs = session.client("ecs")
    cluster = outputs.get("ClusterName") or f"{STACK_NAME}-cluster"
    try:
        tasks = ecs.list_tasks(cluster=cluster)["taskArns"]
        print(f"\n  Running tasks: {len(tasks)}")
        for arn in tasks:
            task_detail = ecs.describe_tasks(cluster=cluster, tasks=[arn])["tasks"][0]
            started = task_detail.get("startedAt", "")
            status = task_detail.get("lastStatus", "?")
            print(f"    {status} — started {started}")
    except Exception:
        print(f"  Running tasks: 0")

    print()


def cmd_logs(args):
    """Tail recent computation logs."""
    profile = args.profile or os.environ.get("AWS_PROFILE", "default")
    region = args.region or DEFAULT_REGION
    session = get_session(profile, region)

    log_group = f"/ecs/{STACK_NAME}"
    logs_client = session.client("logs")

    print(color(f"\n  Tailing logs: {log_group}\n", "bold"))
    print("  (Press Ctrl+C to stop)\n")

    start_time = int((datetime.utcnow() - timedelta(minutes=args.minutes)).timestamp() * 1000)
    seen = set()

    try:
        while True:
            try:
                resp = logs_client.filter_log_events(
                    logGroupName=log_group,
                    startTime=start_time,
                    interleaved=True,
                    limit=50,
                )
            except logs_client.exceptions.ResourceNotFoundException:
                print(color("  No logs yet (no tasks have run).", "yellow"))
                break

            for event in resp.get("events", []):
                eid = event["eventId"]
                if eid in seen:
                    continue
                seen.add(eid)
                ts = datetime.fromtimestamp(event["timestamp"] / 1000).strftime("%H:%M:%S")
                msg = event["message"].strip()
                print(f"  [{ts}] {msg}")
                start_time = event["timestamp"] + 1

            if not args.follow:
                break
            time.sleep(2)
    except KeyboardInterrupt:
        print("\n  Stopped.")


def cmd_costs(args):
    """Show estimated costs from recent tasks."""
    profile = args.profile or os.environ.get("AWS_PROFILE", "default")
    region = args.region or DEFAULT_REGION
    session = get_session(profile, region)

    print(color("\n  Cost Estimate (last 30 days)\n", "bold"))

    # Check ECS task history via stopped tasks
    ecs = session.client("ecs")
    cluster = f"{STACK_NAME}-cluster"

    # Fargate pricing: $0.04048/vCPU/hr + $0.004445/GB/hr
    # Our config: 4 vCPU, 16 GB
    vcpu_cost_per_sec = 0.04048 / 3600
    mem_cost_per_sec = 0.004445 * 16 / 3600
    cost_per_sec = (vcpu_cost_per_sec * 4) + mem_cost_per_sec

    try:
        # List stopped tasks (completed jobs)
        stopped = ecs.list_tasks(cluster=cluster, desiredStatus="STOPPED")["taskArns"]
        total_seconds = 0
        task_count = len(stopped)

        if stopped:
            details = ecs.describe_tasks(cluster=cluster, tasks=stopped[:100])["tasks"]
            for t in details:
                started = t.get("startedAt")
                stopped_at = t.get("stoppedAt")
                if started and stopped_at:
                    duration = (stopped_at - started).total_seconds()
                    total_seconds += duration

        total_cost = total_seconds * cost_per_sec
        running = ecs.list_tasks(cluster=cluster, desiredStatus="RUNNING")["taskArns"]

        print(f"  Tasks completed:  {task_count}")
        print(f"  Tasks running:    {len(running)}")
        print(f"  Total compute:    {total_seconds/60:.1f} minutes")
        print(f"  Estimated cost:   ${total_cost:.4f}")
        print(f"  (4 vCPU / 16 GB @ ${cost_per_sec*3600:.4f}/hr)")
        print()
        print(f"  Idle cost:        {color('$0.00', 'green')} (API Gateway + Lambda)")
        print()

    except Exception as e:
        print(f"  Could not retrieve task history: {e}")
        print(f"  Your idle cost is $0.00 (no always-on resources).")
        print()


def cmd_teardown(args):
    """Delete the stack — stops all costs."""
    profile = args.profile or os.environ.get("AWS_PROFILE", "default")
    region = args.region or DEFAULT_REGION
    session = get_session(profile, region)

    status, outputs = get_stack_outputs(session)
    if not status:
        print(color("  Stack not found. Nothing to tear down.", "yellow"))
        return

    print(color("\n  Teardown Mode 2 Worker\n", "bold"))
    print(f"  Stack:  {STACK_NAME}")
    print(f"  Status: {status}")
    print(f"  Region: {region}")
    print()

    if not args.yes:
        confirm = input(color("  Are you sure? This will delete all resources. [y/N]: ", "yellow"))
        if confirm.lower() != "y":
            print("  Cancelled.")
            return

    print("  Deleting stack...")
    cf = session.client("cloudformation")
    cf.delete_stack(StackName=STACK_NAME)

    print("  Waiting for deletion...")
    waiter = cf.get_waiter("stack_delete_complete")
    waiter.wait(StackName=STACK_NAME, WaiterConfig={"Delay": 10, "MaxAttempts": 30})
    print(color("  ✓ Stack deleted. All costs stopped.", "green"))
    print()


# ═══════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════
def main():
    parser = argparse.ArgumentParser(
        description="MR Optimum Mode 2 — Worker Manager",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Commands:
  deploy    Deploy the worker stack to your AWS account
  status    Check worker health and running tasks
  logs      View computation logs
  costs     Show cost estimates
  teardown  Delete everything (stop all costs)

GUI mode:
  python manage.py --gui     Opens a graphical interface (no CLI knowledge needed)
        """,
    )
    parser.add_argument("command", nargs="?", choices=["deploy", "status", "logs", "costs", "teardown"],
                        help="Command to run (optional if --gui)")
    parser.add_argument("--gui", "-g", action="store_true", help="Open graphical interface")
    parser.add_argument("--profile", "-p", help="AWS CLI profile")
    parser.add_argument("--region", "-r", help="AWS region")
    parser.add_argument("--email", "-e", help="CloudMR email (for deploy)")
    parser.add_argument("--password", help="CloudMR password (for deploy)")
    parser.add_argument("--api-key", help="Worker API key (for deploy)")
    parser.add_argument("--alias", help="Worker alias (for deploy)")
    parser.add_argument("--yes", "-y", action="store_true", help="Skip confirmations")
    parser.add_argument("--follow", "-f", action="store_true", help="Follow logs in real-time")
    parser.add_argument("--minutes", "-m", type=int, default=30, help="Minutes of logs to show (default: 30)")

    args = parser.parse_args()

    if args.gui or (not args.command):
        run_gui()
        return

    commands = {
        "deploy": cmd_deploy,
        "status": cmd_status,
        "logs": cmd_logs,
        "costs": cmd_costs,
        "teardown": cmd_teardown,
    }

    commands[args.command](args)


# ═══════════════════════════════════════════════════════════════
# GUI Mode (tkinter)
# ═══════════════════════════════════════════════════════════════
def run_gui():
    """Simple tkinter GUI for non-expert users."""
    try:
        import tkinter as tk
        from tkinter import ttk, scrolledtext, messagebox
    except ImportError:
        print("tkinter not available. Use CLI mode or install python3-tk.")
        sys.exit(1)

    import threading

    root = tk.Tk()
    root.title("MR Optimum — Mode 2 Worker Manager")
    root.geometry("700x600")
    root.resizable(True, True)

    # ─── Variables ───
    var_profile = tk.StringVar(value=os.environ.get("AWS_PROFILE", "default"))
    var_region = tk.StringVar(value=DEFAULT_REGION)
    var_email = tk.StringVar(value=os.environ.get("CLOUDMR_EMAIL", ""))
    var_password = tk.StringVar(value=os.environ.get("CLOUDMR_PASSWORD", ""))
    var_api_key = tk.StringVar(value="")
    var_alias = tk.StringVar(value="My Cloud Worker")

    # ─── Settings Frame ───
    settings_frame = ttk.LabelFrame(root, text="Settings", padding=10)
    settings_frame.pack(fill="x", padx=10, pady=5)

    row = 0
    for label, var, show in [
        ("AWS Profile:", var_profile, None),
        ("AWS Region:", var_region, None),
        ("CloudMR Email:", var_email, None),
        ("CloudMR Password:", var_password, "*"),
        ("Worker API Key:", var_api_key, None),
        ("Worker Alias:", var_alias, None),
    ]:
        ttk.Label(settings_frame, text=label).grid(row=row, column=0, sticky="w", pady=2)
        entry = ttk.Entry(settings_frame, textvariable=var, width=45)
        if show:
            entry.config(show=show)
        entry.grid(row=row, column=1, sticky="ew", pady=2, padx=(5, 0))
        row += 1

    settings_frame.columnconfigure(1, weight=1)

    # ─── Buttons Frame ───
    btn_frame = ttk.Frame(root, padding=5)
    btn_frame.pack(fill="x", padx=10)

    # ─── Log Output ───
    log_frame = ttk.LabelFrame(root, text="Output", padding=5)
    log_frame.pack(fill="both", expand=True, padx=10, pady=5)

    log_text = scrolledtext.ScrolledText(log_frame, height=15, font=("Courier", 10), state="disabled")
    log_text.pack(fill="both", expand=True)

    def log(msg):
        log_text.config(state="normal")
        log_text.insert("end", msg + "\n")
        log_text.see("end")
        log_text.config(state="disabled")

    def clear_log():
        log_text.config(state="normal")
        log_text.delete("1.0", "end")
        log_text.config(state="disabled")

    def make_args():
        """Build a fake args namespace from GUI fields."""
        ns = argparse.Namespace()
        ns.profile = var_profile.get() or None
        ns.region = var_region.get() or None
        ns.email = var_email.get() or None
        ns.password = var_password.get() or None
        ns.api_key = var_api_key.get() or None
        ns.alias = var_alias.get() or None
        ns.yes = True
        ns.follow = False
        ns.minutes = 60
        return ns

    def run_in_thread(fn):
        """Run a command in a background thread, capturing print output."""
        import io
        clear_log()

        def wrapper():
            old_stdout = sys.stdout
            sys.stdout = buffer = io.StringIO()
            try:
                fn(make_args())
            except Exception as e:
                print(f"\nError: {e}")
            finally:
                sys.stdout = old_stdout
                output = buffer.getvalue()
                # Strip ANSI codes for GUI
                import re
                clean = re.sub(r'\033\[[0-9;]*m', '', output)
                root.after(0, lambda: log(clean))

        threading.Thread(target=wrapper, daemon=True).start()

    ttk.Button(btn_frame, text="Deploy", command=lambda: run_in_thread(cmd_deploy)).pack(side="left", padx=3)
    ttk.Button(btn_frame, text="Status", command=lambda: run_in_thread(cmd_status)).pack(side="left", padx=3)
    ttk.Button(btn_frame, text="Logs", command=lambda: run_in_thread(cmd_logs)).pack(side="left", padx=3)
    ttk.Button(btn_frame, text="Costs", command=lambda: run_in_thread(cmd_costs)).pack(side="left", padx=3)
    ttk.Button(btn_frame, text="Teardown", command=lambda: run_in_thread(cmd_teardown)).pack(side="left", padx=3)
    ttk.Button(btn_frame, text="Clear", command=clear_log).pack(side="right", padx=3)

    root.mainloop()


if __name__ == "__main__":
    main()
