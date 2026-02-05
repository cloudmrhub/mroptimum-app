#!/bin/bash
# filepath: /data/PROJECTS/mroptimum-app/scripts/test-queue-job.sh

# =============================================================================
# Test Queue Job Script for MR Optimum via CloudMR Brain
# =============================================================================
# This script tests the full pipeline:
# 1. Login to CloudMR Brain
# 2. Create a pipeline request
# 3. Queue the job for execution
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Override these with environment variables or edit directly
CLOUDMR_API_URL="${CLOUDMR_API_URL:-https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod}"
CLOUDMR_EMAIL="${CLOUDMR_EMAIL:-}"
CLOUDMR_PASSWORD="${CLOUDMR_PASSWORD:-}"

# MR Optimum CloudApp name
CLOUDAPP_NAME="${CLOUDAPP_NAME:-MR Optimum}"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing=()
    for cmd in curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        exit 1
    fi
    
    log_success "All dependencies found"
}

# =============================================================================
# Authentication
# =============================================================================

login() {
    log_info "Logging in to CloudMR Brain..."
    
    # Prompt for credentials if not set
    if [[ -z "$CLOUDMR_EMAIL" ]]; then
        read -p "Enter CloudMR Brain email: " CLOUDMR_EMAIL
    fi
    
    if [[ -z "$CLOUDMR_PASSWORD" ]]; then
        read -s -p "Enter CloudMR Brain password: " CLOUDMR_PASSWORD
        echo
    fi
    
    # Use jq to properly escape special characters in JSON
    local payload
    payload=$(jq -n --arg email "$CLOUDMR_EMAIL" --arg password "$CLOUDMR_PASSWORD" \
        '{email: $email, password: $password}')
    
    local response
    response=$(curl -s -X POST "${CLOUDMR_API_URL}/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    # Check for success
    local success
    success=$(echo "$response" | jq -r '.success // false')
    
    if [[ "$success" != "true" ]]; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.message // "Unknown error"')
        log_error "Login failed: $error_msg"
        exit 1
    fi
    
    # Extract tokens (API returns snake_case: id_token, access_token, etc.)
    ID_TOKEN=$(echo "$response" | jq -r '.id_token // .idToken // empty')
    ACCESS_TOKEN=$(echo "$response" | jq -r '.access_token // .accessToken // empty')
    REFRESH_TOKEN=$(echo "$response" | jq -r '.refresh_token // .refreshToken // empty')
    USER_ID=$(echo "$response" | jq -r '.user_id // .userId // empty')
    
    if [[ -z "$ID_TOKEN" ]]; then
        log_error "Failed to extract ID token from response"
        echo "Response: $response"
        exit 1
    fi
    
    # Export for other functions
    export ID_TOKEN ACCESS_TOKEN REFRESH_TOKEN USER_ID
    
    log_success "Login successful"
    log_info "ID Token (first 50 chars): ${ID_TOKEN:0:50}..."
}

# =============================================================================
# Get User Profile
# =============================================================================

get_profile() {
    log_info "Fetching user profile..."
    
    local response
    response=$(curl -s -X GET "${CLOUDMR_API_URL}/api/auth/profile" \
        -H "Authorization: Bearer ${ID_TOKEN}")
    
    USER_ID=$(echo "$response" | jq -r '.userId // .sub // empty')
    USERNAME=$(echo "$response" | jq -r '.username // .email // empty')
    
    if [[ -z "$USER_ID" ]]; then
        log_warning "Could not extract userId from profile"
        echo "Profile response: $response"
    else
        log_success "User ID: $USER_ID"
        log_info "Username: $USERNAME"
    fi
}

# =============================================================================
# List CloudApps
# =============================================================================

list_cloudapps() {
    log_info "Listing available CloudApps..."
    
    local response
    response=$(curl -s -X GET "${CLOUDMR_API_URL}/api/cloudapp/list" \
        -H "Authorization: Bearer ${ID_TOKEN}")
    
    echo "CloudApps:"
    echo "$response" | jq -r '.apps[]? | "  - \(.name) (ID: \(.appId))"' 2>/dev/null || echo "$response"
    
    # Find MR Optimum app ID - API returns {apps: [...], count: N}
    CLOUDAPP_ID=$(echo "$response" | jq -r --arg name "$CLOUDAPP_NAME" '.apps[]? | select(.name == $name) | .appId // empty' | head -1)
    
    if [[ -z "$CLOUDAPP_ID" ]]; then
        log_warning "CloudApp '$CLOUDAPP_NAME' not found"
        log_info "Available apps:"
        echo "$response" | jq -r '.apps[]?.name' 2>/dev/null
    else
        log_success "Found CloudApp '$CLOUDAPP_NAME' with ID: $CLOUDAPP_ID"
    fi
}

# =============================================================================
# List Computing Units
# =============================================================================

list_computing_units() {
    log_info "Listing computing units..."
    
    local response
    response=$(curl -s -X GET "${CLOUDMR_API_URL}/api/computing-unit/list" \
        -H "Authorization: Bearer ${ID_TOKEN}")
    
    echo "Computing Units:"
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
}

# =============================================================================
# Create Pipeline Request
# =============================================================================

create_pipeline_request() {
    log_info "Creating pipeline request..."
    
    if [[ -z "$CLOUDAPP_ID" ]]; then
        log_error "CloudApp ID not set. Run list_cloudapps first."
        exit 1
    fi
    
    # Create a simple test pipeline request
    local payload
    payload=$(cat <<EOF
{
    "cloudapp_id": "${CLOUDAPP_ID}",
    "name": "Test Pipeline $(date +%Y%m%d-%H%M%S)",
    "description": "Test pipeline created by test-queue-job.sh"
}
EOF
)
    
    log_info "Pipeline request payload:"
    echo "$payload" | jq '.'
    
    local response
    response=$(curl -s -X POST "${CLOUDMR_API_URL}/api/pipeline/request" \
        -H "Authorization: Bearer ${ID_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    PIPELINE_ID=$(echo "$response" | jq -r '.pipeline // .pipelineId // .id // empty')
    
    if [[ -z "$PIPELINE_ID" ]]; then
        log_error "Failed to create pipeline request"
        echo "Response: $response"
        exit 1
    fi
    
    log_success "Pipeline created with ID: $PIPELINE_ID"
    echo "Full response:"
    echo "$response" | jq '.'
}

# =============================================================================
# Queue Job
# =============================================================================

queue_job() {
    log_info "Queueing job for execution..."
    
    if [[ -z "$PIPELINE_ID" ]]; then
        log_error "Pipeline ID not set. Run create_pipeline_request first."
        exit 1
    fi
    
    # This is the payload for MR Optimum - adjust based on your actual task requirements
    local payload
    payload=$(cat <<EOF
{
    "pipeline": "${PIPELINE_ID}",
    "cloudapp_id": "${CLOUDAPP_ID}",
    "task": {
        "type": "snr_calculation",
        "parameters": {
            "test_mode": true,
            "echo": "Hello from test-queue-job.sh"
        }
    }
}
EOF
)
    
    log_info "Queue job payload:"
    echo "$payload" | jq '.'
    
    local response
    response=$(curl -s -X POST "${CLOUDMR_API_URL}/api/pipeline/queue_job" \
        -H "Authorization: Bearer ${ID_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    log_info "Queue job response:"
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
    
    # Check if job was queued successfully
    if echo "$response" | jq -e '.executionArn // .taskId // .success' &>/dev/null; then
        log_success "Job queued successfully!"
        EXECUTION_ARN=$(echo "$response" | jq -r '.executionArn // empty')
        if [[ -n "$EXECUTION_ARN" ]]; then
            log_info "Execution ARN: $EXECUTION_ARN"
        fi
    else
        log_warning "Job may not have been queued. Check response above."
    fi
}

# =============================================================================
# List User Pipelines
# =============================================================================

list_pipelines() {
    log_info "Listing user pipelines..."
    
    local response
    response=$(curl -s -X GET "${CLOUDMR_API_URL}/api/pipeline" \
        -H "Authorization: Bearer ${ID_TOKEN}")
    
    echo "Pipelines:"
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
}

# =============================================================================
# List Pipelines by CloudApp
# =============================================================================

list_pipelines_by_app() {
    log_info "Listing pipelines for CloudApp: $CLOUDAPP_NAME..."
    
    if [[ -z "$CLOUDAPP_ID" ]]; then
        log_warning "CloudApp ID not set, listing all pipelines"
        local response
        response=$(curl -s -X GET "${CLOUDMR_API_URL}/api/pipeline/list" \
            -H "Authorization: Bearer ${ID_TOKEN}")
    else
        local response
        response=$(curl -s -X GET "${CLOUDMR_API_URL}/api/pipeline/list/${CLOUDAPP_ID}" \
            -H "Authorization: Bearer ${ID_TOKEN}")
    fi
    
    echo "Pipelines:"
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
}

# =============================================================================
# Check Data
# =============================================================================

list_data() {
    log_info "Listing user data..."
    
    local response
    response=$(curl -s -X GET "${CLOUDMR_API_URL}/api/data" \
        -H "Authorization: Bearer ${ID_TOKEN}")
    
    echo "User Data:"
    echo "$response" | jq '.' 2>/dev/null || echo "$response"
}

# =============================================================================
# Interactive Menu
# =============================================================================

show_menu() {
    echo ""
    echo "=========================================="
    echo "  CloudMR Brain - MR Optimum Test Menu"
    echo "=========================================="
    echo "  1) Login"
    echo "  2) Get Profile"
    echo "  3) List CloudApps"
    echo "  4) List Computing Units"
    echo "  5) List User Data"
    echo "  6) List Pipelines"
    echo "  7) List Pipelines by App"
    echo "  8) Create Pipeline Request"
    echo "  9) Queue Job"
    echo " 10) Full Test (1-9)"
    echo "  0) Exit"
    echo "=========================================="
    read -p "Select option: " choice
    
    case $choice in
        1) login ;;
        2) get_profile ;;
        3) list_cloudapps ;;
        4) list_computing_units ;;
        5) list_data ;;
        6) list_pipelines ;;
        7) list_pipelines_by_app ;;
        8) create_pipeline_request ;;
        9) queue_job ;;
        10) full_test ;;
        0) exit 0 ;;
        *) log_error "Invalid option" ;;
    esac
    
    show_menu
}

# =============================================================================
# Full Test
# =============================================================================

full_test() {
    log_info "Running full test sequence..."
    
    login
    get_profile
    list_cloudapps
    list_computing_units
    
    if [[ -n "$CLOUDAPP_ID" ]]; then
        create_pipeline_request
        queue_job
        echo ""
        log_success "Full test completed!"
        log_info "Check AWS Step Functions console or CloudMR Brain for job status"
    else
        log_error "Cannot proceed without CloudApp ID"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo "=========================================="
    echo "  CloudMR Brain - MR Optimum Job Tester"
    echo "=========================================="
    echo ""
    echo "API URL: $CLOUDMR_API_URL"
    echo ""
    
    check_dependencies
    
    # Source exports if available
    if [[ -f "exports.sh" ]]; then
        log_info "Sourcing exports.sh..."
        source exports.sh
    fi
    
    if [[ -f "exports.mode1.sh" ]]; then
        log_info "Sourcing exports.mode1.sh..."
        source exports.mode1.sh
    fi
    
    # Check for command line arguments
    case "${1:-}" in
        --login)
            login
            ;;
        --full)
            full_test
            ;;
        --list-apps)
            login
            list_cloudapps
            ;;
        --list-cu)
            login
            list_computing_units
            ;;
        --menu|"")
            show_menu
            ;;
        *)
            echo "Usage: $0 [--login|--full|--list-apps|--list-cu|--menu]"
            echo ""
            echo "Options:"
            echo "  --login     Just login and print token"
            echo "  --full      Run full test sequence"
            echo "  --list-apps Login and list CloudApps"
            echo "  --list-cu   Login and list Computing Units"
            echo "  --menu      Interactive menu (default)"
            exit 1
            ;;
    esac
}

main "$@"