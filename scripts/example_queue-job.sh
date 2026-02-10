#!/bin/bash
# =============================================================================
# Queue Job Script for MR Optimum via CloudMR Brain
# =============================================================================
# Usage:
#   source exports_user.sh
#   ./scripts/queue-job.sh
#
# Or with inline credentials:
#   CLOUDMR_EMAIL="u@user.com" CLOUDMR_PASSWORD='password' ./scripts/queue-job.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLOUDMR_API_URL="${CLOUDMR_API_URL:-https://f41j488v7j.execute-api.us-east-1.amazonaws.com/Prod}"
CLOUDAPP_NAME="${CLOUDAPP_NAME:-MR Optimum}"
COMPUTING_UNIT_MODE="${COMPUTING_UNIT_MODE:-}"

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Step 1: Login and get token
# =============================================================================
login() {
    log_info "Step 1: Logging in to CloudMR Brain..."
    
    if [[ -z "$CLOUDMR_EMAIL" || -z "$CLOUDMR_PASSWORD" ]]; then
        log_error "CLOUDMR_EMAIL and CLOUDMR_PASSWORD must be set"
        echo "  Run: source exports_user.sh"
        exit 1
    fi
    
    # Use jq to safely escape special characters in JSON
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
    
    # Extract tokens (snake_case from API)
    export ID_TOKEN=$(echo "$response" | jq -r '.id_token')
    export ACCESS_TOKEN=$(echo "$response" | jq -r '.access_token')
    export REFRESH_TOKEN=$(echo "$response" | jq -r '.refresh_token')
    export USER_ID=$(echo "$response" | jq -r '.user_id')
    
    log_success "Logged in as: $CLOUDMR_EMAIL (user_id: $USER_ID)"
}

# =============================================================================
# Step 2: Find CloudApp
# =============================================================================
find_cloudapp() {
    log_info "Step 2: Finding CloudApp '$CLOUDAPP_NAME'..."
    
    local response
    response=$(curl -s -X GET "${CLOUDMR_API_URL}/api/cloudapp/list" \
        -H "Authorization: Bearer ${ID_TOKEN}")
    
    # API returns {apps: [...], count: N} - extract apps array first
    export CLOUDAPP_ID=$(echo "$response" | jq -r --arg name "$CLOUDAPP_NAME" \
        '.apps[]? | select(.name == $name) | .appId // empty' | head -1)
    
    if [[ -z "$CLOUDAPP_ID" ]]; then
        log_error "CloudApp '$CLOUDAPP_NAME' not found"
        echo "Available CloudApps:"
        echo "$response" | jq -r '.apps[]? | "  - \(.name) (ID: \(.appId))"'
        exit 1
    fi
    
    log_success "Found CloudApp ID: $CLOUDAPP_ID"
}

# =============================================================================
# Step 3: Queue Job (creates pipeline + queues job in one call)
# =============================================================================
queue_job() {
    log_info "Step 3: Queueing job (pipeline will be created automatically)..."
    
    local job_alias="Job-$(date +%Y%m%d-%H%M%S)"
    
    # Build the job payload - uses cloudapp_name instead of cloudapp_id
    local task_payload
    if [[ -n "$COMPUTING_UNIT_MODE" ]]; then
        task_payload=$(jq -n \
            --arg cloudapp_name "$CLOUDAPP_NAME" \
            --arg alias "$job_alias" \
            --arg computing_unit_mode "$COMPUTING_UNIT_MODE" \
            --arg timestamp "$(date -Iseconds)" \
            '{
                cloudapp_name: $cloudapp_name,
                computing_unit_mode: $computing_unit_mode,
                alias: $alias,
                task: {
                    type: "snr_calculation",
                    parameters: {
                        test_mode: true,
                        timestamp: $timestamp,
                        echo: "Hello from queue-job.sh"
                    }
                }
            }')
    else
        task_payload=$(jq -n \
            --arg cloudapp_name "$CLOUDAPP_NAME" \
            --arg alias "$job_alias" \
            --arg timestamp "$(date -Iseconds)" \
            '{
                cloudapp_name: $cloudapp_name,
                alias: $alias,
                task: {
                    type: "snr_calculation",
                    parameters: {
                        test_mode: true,
                        timestamp: $timestamp,
                        echo: "Hello from queue-job.sh"
                    }
                }
            }')
    fi
    
    echo ""
    log_info "Job payload:"
    echo "$task_payload" | jq .
    echo ""
    
    local response
    response=$(curl -s -X POST "${CLOUDMR_API_URL}/api/pipeline/queue_job" \
        -H "Authorization: Bearer ${ID_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$task_payload")
    
    echo ""
    log_info "Queue response:"
    echo "$response" | jq .
    
    # Extract execution ARN if present
    export EXECUTION_ARN=$(echo "$response" | jq -r '.executionArn // empty')
    export TASK_ID=$(echo "$response" | jq -r '.taskId // .task_id // empty')
    export PIPELINE_ID=$(echo "$response" | jq -r '.pipeline // .pipelineId // empty')
    
    if [[ -n "$EXECUTION_ARN" ]]; then
        echo ""
        log_success "Job queued successfully!"
        echo ""
        echo "=========================================="
        echo "  Execution Details"
        echo "=========================================="
        echo "  Execution ARN: $EXECUTION_ARN"
        echo "  Pipeline ID:   $PIPELINE_ID"
        echo "  CloudApp:      $CLOUDAPP_NAME"
        echo ""
        echo "  Monitor at AWS Console:"
        echo "  https://us-east-1.console.aws.amazon.com/states/home?region=us-east-1#/executions/details/${EXECUTION_ARN}"
        echo "=========================================="
    elif [[ -n "$TASK_ID" ]]; then
        log_success "Job queued with Task ID: $TASK_ID"
    else
        log_error "Job may not have been queued. Check response above."
    fi
}

# =============================================================================
# Step 5: Export tokens for reuse
# =============================================================================
export_tokens() {
    echo ""
    log_info "Tokens exported to environment. To reuse in this session:"
    echo ""
    echo "  export ID_TOKEN='${ID_TOKEN:0:50}...'"
    echo "  export USER_ID='$USER_ID'"
    echo "  export CLOUDAPP_ID='$CLOUDAPP_ID'"
    echo "  export PIPELINE_ID='$PIPELINE_ID'"
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo "=========================================="
    echo "  CloudMR Brain - Queue Job"
    echo "=========================================="
    echo "  API: $CLOUDMR_API_URL"
    echo "=========================================="
    echo ""
    
    login
    find_cloudapp
    queue_job
    export_tokens
}

main "$@"
