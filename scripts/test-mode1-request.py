#!/usr/bin/env python3
"""
Test Mode 1 Deployment via CloudMR Brain API

This script:
1. Authenticates with CloudMR Brain
2. Submits a calculation request for mroptimum
3. Monitors the job status
4. Reports success/failure

Usage:
    export CLOUDMR_API_URL=https://your-cloudmr-brain-api.com
    export CLOUDMR_USERNAME=your_username
    export CLOUDMR_PASSWORD=your_password
    
    python scripts/test-mode1-request.py
"""

import os
import sys
import json
import time
import requests
from typing import Dict, Optional

# Configuration from environment
CLOUDMR_API_URL = os.getenv("CLOUDMR_API_URL")
CLOUDMR_USERNAME = os.getenv("CLOUDMR_USERNAME")
CLOUDMR_PASSWORD = os.getenv("CLOUDMR_PASSWORD")
CLOUDMR_TOKEN = os.getenv("CLOUDMR_TOKEN")  # Optional: skip login if token provided

# Test configuration
APP_ID = "mroptimum"
POLL_INTERVAL = 5  # seconds
MAX_WAIT = 600  # 10 minutes


def print_header(text: str):
    """Print formatted header"""
    print("\n" + "=" * 70)
    print(f"  {text}")
    print("=" * 70 + "\n")


def login(api_url: str, username: str, password: str) -> str:
    """Login and get auth token"""
    print(f"Logging in as {username}...")
    
    response = requests.post(
        f"{api_url}/api/auth/login",
        json={
            "username": username,
            "password": password
        }
    )
    
    if response.status_code != 200:
        print(f"❌ Login failed: {response.status_code}")
        print(response.text)
        sys.exit(1)
    
    data = response.json()
    token = data.get("token")
    
    if not token:
        print("❌ No token in response")
        print(json.dumps(data, indent=2))
        sys.exit(1)
    
    print(f"✅ Login successful")
    return token


def list_computing_units(api_url: str, token: str, app_id: str) -> list:
    """List available computing units for the app"""
    print(f"Listing computing units for {app_id}...")
    
    response = requests.get(
        f"{api_url}/api/computing-unit/list",
        headers={"Authorization": f"Bearer {token}"},
        params={"appId": app_id}
    )
    
    if response.status_code != 200:
        print(f"⚠ Failed to list computing units: {response.status_code}")
        return []
    
    units = response.json()
    print(f"Found {len(units)} computing unit(s)")
    
    for unit in units:
        mode = unit.get("mode", "unknown")
        provider = unit.get("provider", "unknown")
        is_default = unit.get("isDefault", False)
        print(f"  - {mode} ({provider}) {'[DEFAULT]' if is_default else ''}")
    
    return units


def submit_calculation(api_url: str, token: str, payload: Dict) -> str:
    """Submit a calculation request and return pipeline_id"""
    print("Submitting calculation request...")
    
    response = requests.post(
        f"{api_url}/api/pipeline/request",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        },
        json=payload
    )
    
    if response.status_code not in [200, 201]:
        print(f"❌ Request failed: {response.status_code}")
        print(response.text)
        sys.exit(1)
    
    data = response.json()
    pipeline_id = data.get("pipelineId") or data.get("id")
    
    if not pipeline_id:
        print("❌ No pipeline ID in response")
        print(json.dumps(data, indent=2))
        sys.exit(1)
    
    print(f"✅ Request submitted")
    print(f"   Pipeline ID: {pipeline_id}")
    return pipeline_id


def check_status(api_url: str, token: str, pipeline_id: str) -> Dict:
    """Check pipeline status"""
    response = requests.get(
        f"{api_url}/api/pipeline/status/{pipeline_id}",
        headers={"Authorization": f"Bearer {token}"}
    )
    
    if response.status_code != 200:
        return {"status": "UNKNOWN", "error": response.text}
    
    return response.json()


def monitor_pipeline(api_url: str, token: str, pipeline_id: str):
    """Monitor pipeline until completion"""
    print(f"\nMonitoring pipeline {pipeline_id}...")
    print("Status updates (Ctrl+C to stop):\n")
    
    start_time = time.time()
    last_status = None
    
    try:
        while True:
            elapsed = int(time.time() - start_time)
            
            if elapsed > MAX_WAIT:
                print(f"\n⚠ Timeout after {MAX_WAIT}s")
                break
            
            status_data = check_status(api_url, token, pipeline_id)
            current_status = status_data.get("status", "UNKNOWN")
            
            if current_status != last_status:
                timestamp = time.strftime("%H:%M:%S")
                print(f"[{timestamp}] Status: {current_status}")
                last_status = current_status
            
            # Terminal states
            if current_status in ["SUCCEEDED", "COMPLETED", "DONE"]:
                print(f"\n✅ Pipeline SUCCEEDED in {elapsed}s")
                print("\nFinal status:")
                print(json.dumps(status_data, indent=2))
                return
            
            elif current_status in ["FAILED", "ERROR"]:
                print(f"\n❌ Pipeline FAILED")
                print("\nError details:")
                print(json.dumps(status_data, indent=2))
                sys.exit(1)
            
            elif current_status == "UNKNOWN":
                print(f"\n⚠ Unknown status")
                print(json.dumps(status_data, indent=2))
                break
            
            time.sleep(POLL_INTERVAL)
    
    except KeyboardInterrupt:
        print("\n\n⚠ Monitoring stopped by user")
        print(f"Pipeline ID: {pipeline_id}")
        print(f"Check status: {api_url}/api/pipeline/status/{pipeline_id}")


def create_test_payload() -> Dict:
    """Create a minimal test payload for mroptimum"""
    return {
        "appId": APP_ID,
        "task": {
            "name": "test_calculation",
            "type": "brain",
            "options": {
                "test": True
            }
        },
        "inputs": {
            "test_input": "s3://test-bucket/test-data.dat"
        },
        "output": {
            "format": "json"
        }
    }


def main():
    print_header("Mode 1 Test - CloudMR Brain API")
    
    # Validate configuration
    if not CLOUDMR_API_URL:
        print("❌ CLOUDMR_API_URL not set")
        print("\nSet environment variables:")
        print("  export CLOUDMR_API_URL=https://your-api.com")
        print("  export CLOUDMR_USERNAME=your_username")
        print("  export CLOUDMR_PASSWORD=your_password")
        sys.exit(1)
    
    print(f"API URL: {CLOUDMR_API_URL}")
    print(f"App ID:  {APP_ID}\n")
    
    # Get auth token
    if CLOUDMR_TOKEN:
        print("Using provided token")
        token = CLOUDMR_TOKEN
    elif CLOUDMR_USERNAME and CLOUDMR_PASSWORD:
        token = login(CLOUDMR_API_URL, CLOUDMR_USERNAME, CLOUDMR_PASSWORD)
    else:
        print("❌ No authentication provided")
        print("Set CLOUDMR_TOKEN or CLOUDMR_USERNAME+CLOUDMR_PASSWORD")
        sys.exit(1)
    
    # List available computing units
    units = list_computing_units(CLOUDMR_API_URL, token, APP_ID)
    
    if not units:
        print("⚠ No computing units found for mroptimum")
        print("Make sure Mode 1 is deployed and registered")
    
    # Create test payload
    payload = create_test_payload()
    
    print("\nTest payload:")
    print(json.dumps(payload, indent=2))
    
    # Submit request
    pipeline_id = submit_calculation(CLOUDMR_API_URL, token, payload)
    
    # Monitor execution
    monitor_pipeline(CLOUDMR_API_URL, token, pipeline_id)


if __name__ == "__main__":
    main()
