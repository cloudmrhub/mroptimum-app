#!/usr/bin/env bash
#
# Register MR Optimum Computing Unit with CloudMR Brain
# 
# Usage:
#   export CLOUDMR_EMAIL="your@email.com"
#   export CLOUDMR_PASSWORD="yourpassword"
#   export CLOUDMR_API_URL="https://..."
#   ./scripts/register-computing-unit.sh
#
# Optional environment variables:
#   APP_NAME (default: "MR Optimum")
#   MODE (default: "mode_1")
#   AWS_ACCOUNT_ID (default: from AWS credentials)
#   STATE_MACHINE_ARN (default: auto-detect from CloudFormation)
#   REGION (default: us-east-1)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

APP_NAME="${APP_NAME:-MR Optimum}"
MODE="${MODE:-mode_1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
REGION="${REGION:-us-east-1}"
STATE_MACHINE_ARN="${STATE_MACHINE_ARN:-}"
# Accept either CLOUDMR_API_URL (new) or CLOUDM_MR_BRAIN (existing exports.sh)
CLOUDMR_API_URL="${CLOUDMR_API_URL:-${CLOUDM_MR_BRAIN:-}}"
CLOUDMR_EMAIL="${CLOUDMR_EMAIL:-}"
CLOUDMR_PASSWORD="${CLOUDMR_PASSWORD:-}"
STACK_NAME="${STACK_NAME:-mroptimum-app}"

# CloudMR Brain buckets (Mode 1 - CloudMRHub managed)
RESULTS_BUCKET="cloudmr-results-cloudmrhub-brain-us-east-1"
FAILED_BUCKET="cloudmr-failed-cloudmrhub-brain-us-east-1"
DATA_BUCKET="cloudmr-data-cloudmrhub-brain-us-east-1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ============================================================================
# Validation
# ============================================================================

validate_inputs() {
    log_info "Validating inputs..."
    
    # Check required tools
    for cmd in curl jq aws; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "$cmd is required but not installed"
            exit 1
        fi
    done
    
    # Check credentials
    if [[ -z "$CLOUDMR_API_URL" ]]; then
        log_error "CLOUDMR_API_URL not set"
        exit 1
    fi
    
    if [[ -z "$CLOUDMR_EMAIL" || -z "$CLOUDMR_PASSWORD" ]]; then
        log_error "CLOUDMR_EMAIL and CLOUDMR_PASSWORD must be set"
        exit 1
    fi
    
    log_success "All dependencies found"
}

# ============================================================================
# Step 1: Login
# ============================================================================

login() {
    log_info "Step 1: Logging in to CloudMR Brain..."
    
    # Use jq to safely escape special characters
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
        local msg
        msg=$(echo "$response" | jq -r '.message // "Unknown error"')
        log_error "Login failed: $msg"
        exit 1
    fi
    
    # Extract token
    export ID_TOKEN=$(echo "$response" | jq -r '.id_token')
    export USER_ID=$(echo "$response" | jq -r '.user_id')
    
    if [[ -z "$ID_TOKEN" ]]; then
        log_error "Failed to extract ID token"
        exit 1
    fi
    
    log_success "Logged in as: $CLOUDMR_EMAIL (user_id: $USER_ID)"
}

# ============================================================================
# Step 2: Get State Machine ARN
# ============================================================================

get_state_machine_arn() {
    if [[ -n "$STATE_MACHINE_ARN" ]]; then
        log_info "Step 2: Using provided STATE_MACHINE_ARN"
        log_info "State Machine ARN: $STATE_MACHINE_ARN"
        return
    fi
    
    log_info "Step 2: Detecting State Machine ARN from CloudFormation..."
    
    # Auto-detect AWS account ID if not provided
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        log_info "Detected AWS Account ID: $AWS_ACCOUNT_ID"
    fi
    
    # Get State Machine ARN from stack outputs
    STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CalculationStateMachineArn`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$STATE_MACHINE_ARN" || "$STATE_MACHINE_ARN" == "None" ]]; then
        log_error "Could not find CalculationStateMachineArn in stack outputs"
        log_info "Checked stack: $STACK_NAME in region: $REGION"
        log_info "Set STATE_MACHINE_ARN manually or ensure the stack is deployed"
        exit 1
    fi
    
    log_success "State Machine ARN: $STATE_MACHINE_ARN"
}

# ============================================================================
# Step 3: Determine Provider and Account
# ============================================================================

determine_provider() {
    log_info "Step 3: Determining provider and account..."
    
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    # CloudMRHub account ID
    CLOUDMRHUB_ACCOUNT="262361552878"
    
    if [[ "$AWS_ACCOUNT_ID" == "$CLOUDMRHUB_ACCOUNT" ]]; then
        # State Machine is in CloudMRHub account → Mode 1
        if [[ "$MODE" == "mode_1" ]]; then
            PROVIDER="cloudmrhub"
            log_success "Mode 1 (CloudMRHub Managed) - Provider: cloudmrhub"
        else
            log_error "State Machine is in CloudMRHub account but MODE is set to $MODE"
            exit 1
        fi
    else
        # State Machine is in user account → Mode 2
        if [[ "$MODE" == "mode_2" ]]; then
            PROVIDER="user"
            log_success "Mode 2 (User Owned) - Provider: user - Account: $AWS_ACCOUNT_ID"
        else
            log_warn "State Machine is in user account ($AWS_ACCOUNT_ID) but MODE is set to $MODE"
            log_info "Overriding MODE to mode_2"
            MODE="mode_2"
            PROVIDER="user"
        fi
    fi
}

# ============================================================================
# Step 4: Register Computing Unit
# ============================================================================

register_computing_unit() {
    log_info "Step 4: Registering computing unit..."
    
    # Build payload based on mode
    local payload
    if [[ "$MODE" == "mode_1" ]]; then
        payload=$(jq -n \
            --arg appName "$APP_NAME" \
            --arg mode "$MODE" \
            --arg provider "$PROVIDER" \
            --arg awsAccountId "$AWS_ACCOUNT_ID" \
            --arg region "$REGION" \
            --arg stateMachineArn "$STATE_MACHINE_ARN" \
            --arg resultsBucket "$RESULTS_BUCKET" \
            --arg failedBucket "$FAILED_BUCKET" \
            --arg dataBucket "$DATA_BUCKET" \
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
                isDefault: true
            }')
    else
        # Mode 2: User-owned
        payload=$(jq -n \
            --arg appName "$APP_NAME" \
            --arg mode "$MODE" \
            --arg provider "$PROVIDER" \
            --arg awsAccountId "$AWS_ACCOUNT_ID" \
            --arg region "$REGION" \
            --arg stateMachineArn "$STATE_MACHINE_ARN" \
            --arg resultsBucket "$RESULTS_BUCKET" \
            --arg failedBucket "$FAILED_BUCKET" \
            --arg dataBucket "$DATA_BUCKET" \
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
                isDefault: false
            }')
    fi
    
    echo ""
    log_info "Registration payload:"
    echo "$payload" | jq .
    echo ""
    
    local response
    response=$(curl -s -X POST "${CLOUDMR_API_URL}/api/computing-unit/register" \
        -H "Authorization: Bearer ${ID_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    log_info "Registration response:"
    echo "$response" | jq . || echo "$response"
    
    # Check for success
    local computing_unit_id
    computing_unit_id=$(echo "$response" | jq -r '.computingUnitId // empty')
    
    if [[ -z "$computing_unit_id" ]]; then
        log_error "Registration failed. See response above."
        exit 1
    fi
    
    log_success "Computing unit registered: $computing_unit_id"
    export COMPUTING_UNIT_ID="$computing_unit_id"
}

# ============================================================================
# Step 5: List Computing Units
# ============================================================================

list_computing_units() {
    log_info "Step 5: Listing computing units..."
    
    local response
    response=$(curl -s -G -H "Authorization: Bearer ${ID_TOKEN}" \
        "${CLOUDMR_API_URL}/api/computing-unit/list" \
        --data-urlencode "app_name=$APP_NAME")
    
    echo ""
    log_info "Available computing units:"
    echo "$response" | jq . || echo "$response"
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo "=========================================="
    echo "  Register Computing Unit"
    echo "=========================================="
    echo "  App: $APP_NAME"
    echo "  Mode: $MODE"
    echo "  Region: $REGION"
    echo "=========================================="
    echo ""
    
    validate_inputs
    login
    get_state_machine_arn
    determine_provider
    register_computing_unit
    list_computing_units
    
    echo ""
    log_success "Registration workflow complete!"
}

main "$@"
