#!/usr/bin/env bash
#
# MR Optimum Job Submission Workflow
#
# Complete workflow: Login → Query Computing Units → Queue Job
#
# Usage:
#   # Interactive mode (prompts for selections)
#   ./scripts/submit-job.sh
#
#   # With mode selection
#   MODE=mode_1 ./scripts/submit-job.sh
#   MODE=mode_2 ./scripts/submit-job.sh
#
#   # With specific computing unit ID
#   COMPUTING_UNIT_ID=uuid ./scripts/submit-job.sh
#
#   # Non-interactive with all parameters
#   CLOUDMR_EMAIL=u@user.com CLOUDMR_PASSWORD=pass \
#   CLOUDMR_API_URL=https://... MODE=mode_1 \
#   APP_NAME="CAMRIE" PIPELINE_ALIAS="brain_calc" \
#   ./scripts/submit-job.sh
#
# Required:
#   CLOUDMR_EMAIL - CloudMR user email
#   CLOUDMR_PASSWORD - CloudMR user password
#   CLOUDMR_API_URL - CloudMR Brain API URL
#
# Optional:
#   MODE - Computing unit mode (mode_1 or mode_2, default: auto-select)
#   COMPUTING_UNIT_ID - Specific computing unit UUID
#   APP_NAME - CloudApp name (default: CAMRIE)
#   PIPELINE_ALIAS - Pipeline alias/name (default: auto-generated)
#   TASK_DEFINITION - Task definition JSON (default: example brain calc)
#   INTERACTIVE - Set to "false" to disable prompts (default: true)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# User inputs
CLOUDMR_EMAIL="${CLOUDMR_EMAIL:-}"
CLOUDMR_PASSWORD="${CLOUDMR_PASSWORD:-}"
# Accept existing variable name used in exports.sh as fallback
CLOUDMR_API_URL="${CLOUDMR_API_URL:-${CLOUDM_MR_BRAIN:-}}"

# Job configuration
APP_NAME="${APP_NAME:-CAMRIE}"
MODE="${MODE:-}"
COMPUTING_UNIT_ID="${COMPUTING_UNIT_ID:-}"
PIPELINE_ALIAS="${PIPELINE_ALIAS:-}"
TASK_DEFINITION="${TASK_DEFINITION:-}"

# Control flow
INTERACTIVE="${INTERACTIVE:-true}"

# State
ID_TOKEN=""
AVAILABLE_UNITS=()
SELECTED_MODE=""
EXECUTION_ARN=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_header()  { echo -e "\n${MAGENTA}════════════════════════════════════════${NC}"; echo -e "${MAGENTA}$1${NC}"; echo -e "${MAGENTA}════════════════════════════════════════${NC}\n"; }

# ============================================================================
# Input Validation
# ============================================================================

validate_inputs() {
    log_header "Step 1: Validating Inputs"
    
    # Check required tools
    for cmd in curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "$cmd is required but not installed"
            exit 1
        fi
    done
    
    # Check required environment variables
    if [[ -z "$CLOUDMR_API_URL" ]]; then
        log_error "CLOUDMR_API_URL not set"
        exit 1
    fi
    
    # Prompt for credentials if not provided
    if [[ -z "$CLOUDMR_EMAIL" ]]; then
        if [[ "$INTERACTIVE" == "true" ]]; then
            read -p "CloudMR Email: " CLOUDMR_EMAIL
        else
            log_error "CLOUDMR_EMAIL not set"
            exit 1
        fi
    fi
    
    if [[ -z "$CLOUDMR_PASSWORD" ]]; then
        if [[ "$INTERACTIVE" == "true" ]]; then
            read -sp "CloudMR Password: " CLOUDMR_PASSWORD
            echo ""
        else
            log_error "CLOUDMR_PASSWORD not set"
            exit 1
        fi
    fi
    
    log_success "All required inputs provided"
    log_info "API URL: $CLOUDMR_API_URL"
    log_info "Email: $CLOUDMR_EMAIL"
}

# ============================================================================
# Step 2: Login
# ============================================================================

login() {
    log_header "Step 2: Authenticating with CloudMR Brain"
    
    log_info "Logging in as: $CLOUDMR_EMAIL"
    
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
        log_error "Authentication failed: $msg"
        exit 1
    fi
    
    # Extract token
    ID_TOKEN=$(echo "$response" | jq -r '.id_token')
    
    if [[ -z "$ID_TOKEN" ]]; then
        log_error "Failed to extract ID token"
        exit 1
    fi
    
    log_success "Authentication successful"
}

# ============================================================================
# Step 3: Query Computing Units
# ============================================================================

query_computing_units() {
    log_header "Step 3: Querying Available Computing Units"
    
    log_info "Fetching computing units for app: $APP_NAME"
    
    local response
    response=$(curl -s -G -H "Authorization: Bearer ${ID_TOKEN}" \
        "${CLOUDMR_API_URL}/api/computing-unit/list" \
        --data-urlencode "app_name=$APP_NAME")
    
    # Parse response robustly: support multiple API shapes
    # - { units: [...] }
    # - { computingUnits: [...] }
    # - { mode_1: [...], mode_2: [...] }
    local units_json
    # Normalize possible API shapes into a JSON array. Use `try`/`catch` so
    # non-JSON or unexpected responses produce an empty array instead of jq
    # failing with "Cannot iterate over null".
    units_json=$(echo "$response" | jq -c '
        try (
            if .units? then .units
            elif .computingUnits? then .computingUnits
            elif (.mode_1? or .mode_2?) then ((.mode_1 // []) + (.mode_2 // []))
            else [] end
        ) catch []')

    local count
    count=$(echo "$units_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        log_error "No computing units found for app: $APP_NAME"
        echo ""
        log_info "Response:"
        echo "$response" | jq .
        exit 1
    fi

    log_success "Found $count computing unit(s)"
    echo ""
    # Normalize provider/account fields and print summary
    echo "$units_json" | jq -c '.[] | {id: .computingUnitId, mode: (.mode // "unknown"), provider: (.provider // .cloudProvider // ""), account: (.awsAccountId // .awsAccountId // "") }' | jq -s .
    echo ""

    # Store units for selection (newline-separated)
    # EXPORT: newline-separated list of computingUnitId values (safe if empty)
    AVAILABLE_UNITS=$(echo "$units_json" | jq -r '.[].computingUnitId // empty')
}

# ============================================================================
# Step 4: Select Computing Unit
# ============================================================================

select_computing_unit() {
    log_header "Step 4: Selecting Computing Unit"
    
    # Priority 1: Explicit computing_unit_id
    if [[ -n "$COMPUTING_UNIT_ID" ]]; then
        log_info "Using explicit COMPUTING_UNIT_ID: $COMPUTING_UNIT_ID"
        return
    fi
    
    # Priority 2: Mode selection
    if [[ -n "$MODE" ]]; then
        log_info "Using MODE: $MODE"
        SELECTED_MODE="$MODE"
        return
    fi
    
    # Priority 3: Interactive selection
    if [[ "$INTERACTIVE" == "true" ]]; then
        echo "Available modes:"
        echo "  1) mode_1 (CloudMRHub Managed)"
        echo "  2) mode_2 (User Owned)"
        echo "  3) Select specific computing unit"
        echo ""
        read -p "Choose option (1-3): " selection
        
        case "$selection" in
            1)
                SELECTED_MODE="mode_1"
                log_info "Selected mode: mode_1 (CloudMRHub Managed)"
                ;;
            2)
                SELECTED_MODE="mode_2"
                log_info "Selected mode: mode_2 (User Owned)"
                ;;
            3)
                echo ""
                echo "Available computing unit IDs:"
                local idx=1
                declare -a units_array
                while IFS= read -r unit_id; do
                    units_array+=("$unit_id")
                    echo "  $idx) $unit_id"
                    ((idx++))
                done <<< "$AVAILABLE_UNITS"
                
                echo ""
                read -p "Choose computing unit (1-$idx): " unit_choice
                COMPUTING_UNIT_ID="${units_array[$((unit_choice-1))]}"
                log_info "Selected computing unit: $COMPUTING_UNIT_ID"
                ;;
            *)
                log_error "Invalid selection"
                exit 1
                ;;
        esac
        return
    fi
    
    # Priority 4: Default to mode_1
    log_warn "No mode or computing_unit_id specified, defaulting to mode_1"
    SELECTED_MODE="mode_1"
}

# ============================================================================
# Step 5: Prepare Job Definition
# ============================================================================

prepare_job_definition() {
    log_header "Step 5: Preparing Job Definition"
    
    # Use provided task definition or create default
    if [[ -z "$TASK_DEFINITION" ]]; then
        log_info "Using default brain calculation task definition"
        TASK_DEFINITION=$(jq -n '{
            task_type: "brain_calculation",
            parameters: {
                input_format: "nifti",
                output_format: "nifti"
            }
        }')
    else
        log_info "Using custom task definition"
    fi
    
    # Generate pipeline alias if not provided
    if [[ -z "$PIPELINE_ALIAS" ]]; then
        PIPELINE_ALIAS="mr-opt-job-$(date +%s)"
        log_info "Generated pipeline alias: $PIPELINE_ALIAS"
    else
        log_info "Using pipeline alias: $PIPELINE_ALIAS"
    fi
    
    log_success "Job definition prepared"
}

# ============================================================================
# Step 6: Queue Job
# ============================================================================

queue_job() {
    log_header "Step 6: Queueing Job with CloudMR Brain"
    
    # Build payload based on selection method
    local payload
    
    if [[ -n "$COMPUTING_UNIT_ID" ]]; then
        # Pattern 3: Queue by specific computing_unit_id
        log_info "Queueing by computing_unit_id: $COMPUTING_UNIT_ID"
        payload=$(jq -n \
            --arg cloudapp_name "$APP_NAME" \
            --arg alias "$PIPELINE_ALIAS" \
            --arg computing_unit_id "$COMPUTING_UNIT_ID" \
            --argjson task "$TASK_DEFINITION" \
            '{
                cloudapp_name: $cloudapp_name,
                alias: $alias,
                computing_unit_id: $computing_unit_id,
                task: $task
            }')
    else
        # Pattern 1 or 2: Queue by mode
        log_info "Queueing by mode: $SELECTED_MODE"
        payload=$(jq -n \
            --arg cloudapp_name "$APP_NAME" \
            --arg alias "$PIPELINE_ALIAS" \
            --arg mode "$SELECTED_MODE" \
            --argjson task "$TASK_DEFINITION" \
            '{
                cloudapp_name: $cloudapp_name,
                alias: $alias,
                mode: $mode,
                task: $task
            }')
    fi
    
    echo ""
    log_info "Job payload:"
    echo "$payload" | jq .
    echo ""
    
    # Submit job
    local response
    response=$(curl -s -X POST "${CLOUDMR_API_URL}/api/pipeline/queue_job" \
        -H "Authorization: Bearer ${ID_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    log_info "CloudMR Brain response:"
    echo "$response" | jq . || echo "$response"
    echo ""
    
    # Extract execution details
    EXECUTION_ARN=$(echo "$response" | jq -r '.executionArn // empty')
    local pipeline_uuid
    pipeline_uuid=$(echo "$response" | jq -r '.pipelineId // empty')
    local computing_unit_used
    computing_unit_used=$(echo "$response" | jq -r '.computingUnit.computingUnitId // empty')
    
    if [[ -z "$EXECUTION_ARN" ]]; then
        log_error "Job queueing failed. See response above."
        exit 1
    fi
    
    log_success "Job queued successfully!"
    log_info "Execution ARN: $EXECUTION_ARN"
    log_info "Pipeline UUID: $pipeline_uuid"
    log_info "Computing Unit: $computing_unit_used"
}

# ============================================================================
# Step 7: Display Summary
# ============================================================================

display_summary() {
    log_header "Job Submission Complete"
    
    echo "Job Details:"
    echo "  App Name: $APP_NAME"
    echo "  Pipeline Alias: $PIPELINE_ALIAS"
    if [[ -n "$COMPUTING_UNIT_ID" ]]; then
        echo "  Computing Unit ID: $COMPUTING_UNIT_ID"
    else
        echo "  Mode: $SELECTED_MODE"
    fi
    echo "  Execution ARN: $EXECUTION_ARN"
    echo ""
    
    echo "Next Steps:"
    echo "  1. Monitor job execution in CloudMR Brain"
    echo "  2. Check results in S3 buckets"
    echo "  3. Use execution ARN to track status:"
    echo "     aws stepfunctions describe-execution --execution-arn \"$EXECUTION_ARN\""
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_header "MR Optimum Job Submission Workflow"
    
    validate_inputs
    login
    query_computing_units
    select_computing_unit
    prepare_job_definition
    queue_job
    display_summary
    
    log_success "Workflow complete!"
}

main "$@"
