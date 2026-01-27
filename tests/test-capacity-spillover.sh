#!/usr/bin/env bash
# ============================================================================
# Test Script: Capacity Spillover (Primary → Spillover Backend Failover)
# 
# Tests the APIM backend pool circuit breaker pattern:
# - Primary backend has limited capacity (10K TPM)
# - When primary is overwhelmed (429 errors), circuit breaker activates
# - Traffic automatically routes to spillover backend (80K TPM)
#
# Prerequisites:
#   - Azure CLI logged in
#   - APIM_SUBSCRIPTION_KEY environment variable set
#   - Deployment completed successfully
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Test configuration (can be overridden via environment variables)
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-apim-aoai-multi-region}"
FRONT_DOOR_ENDPOINT="${FRONT_DOOR_ENDPOINT:-}"
APIM_ENDPOINT="${APIM_ENDPOINT:-}"
APIM_SUBSCRIPTION_KEY="${APIM_SUBSCRIPTION_KEY:-}"

# Test parameters
BURST_SIZE="${BURST_SIZE:-30}"
MAX_TOKENS="${MAX_TOKENS:-500}"

# ============================================================================
# Helper Functions
# ============================================================================

print_header()  { echo -e "\n${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"; echo -e "${BOLD}${BLUE}  $1${NC}"; echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}\n"; }
print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
print_metric()  { echo -e "${CYAN}[DATA]${NC} $1"; }

# Get all but last N lines (macOS compatible alternative to head -n -N)
head_except_last() {
    local n="${1:-2}"
    local total
    total=$(wc -l | tr -d ' ')
    if [[ $total -gt $n ]]; then
        head -n $((total - n))
    fi
}

# ============================================================================
# Configuration Discovery
# ============================================================================

discover_config() {
    print_status "Discovering deployment configuration..."
    
    # Try to get Front Door endpoint from deployment
    if [[ -z "$FRONT_DOOR_ENDPOINT" ]]; then
        FRONT_DOOR_ENDPOINT=$(az deployment sub show \
            --name "$DEPLOYMENT_NAME" \
            --query "properties.outputs.frontDoorEndpointUrl.value" \
            -o tsv 2>/dev/null || echo "")
    fi
    
    # Try to get APIM endpoint from deployment
    if [[ -z "$APIM_ENDPOINT" ]]; then
        APIM_ENDPOINT=$(az deployment sub show \
            --name "$DEPLOYMENT_NAME" \
            --query "properties.outputs.apimGatewayUrl.value" \
            -o tsv 2>/dev/null || echo "")
    fi
    
    # Validate configuration
    if [[ -z "$FRONT_DOOR_ENDPOINT" ]] && [[ -z "$APIM_ENDPOINT" ]]; then
        print_error "Could not discover endpoints. Set FRONT_DOOR_ENDPOINT or APIM_ENDPOINT manually."
        exit 1
    fi
    
    if [[ -z "$APIM_SUBSCRIPTION_KEY" ]]; then
        print_error "APIM_SUBSCRIPTION_KEY environment variable is required."
        echo ""
        echo "To get the subscription key:"
        echo "  1. Go to Azure Portal → API Management → Subscriptions"
        echo "  2. Click 'Show/hide keys' for 'aoai-subscription'"
        echo "  3. Copy the Primary key"
        echo ""
        echo "Then run: export APIM_SUBSCRIPTION_KEY='your-key'"
        exit 1
    fi
    
    echo ""
    print_success "Configuration discovered:"
    [[ -n "$FRONT_DOOR_ENDPOINT" ]] && echo "  Front Door: $FRONT_DOOR_ENDPOINT"
    [[ -n "$APIM_ENDPOINT" ]] && echo "  APIM:       $APIM_ENDPOINT"
    echo ""
}

# ============================================================================
# API Request Functions
# ============================================================================

# Send a single request and return response info
send_request() {
    local endpoint="$1"
    local model="$2"
    local prompt="${3:-Tell me about cloud computing}"
    local max_tokens="${4:-$MAX_TOKENS}"
    
    curl -s -w "\n%{http_code}\n%{time_total}" \
        -X POST "${endpoint}/openai/deployments/${model}/chat/completions?api-version=2024-08-01-preview" \
        -H "Content-Type: application/json" \
        -H "api-key: $APIM_SUBSCRIPTION_KEY" \
        -d "{
            \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}],
            \"max_tokens\": $max_tokens
        }" 2>/dev/null
}

# Send request and parse response
send_and_parse() {
    local endpoint="$1"
    local model="$2"
    local prompt="${3:-Hello}"
    local max_tokens="${4:-10}"
    
    local response
    response=$(send_request "$endpoint" "$model" "$prompt" "$max_tokens")
    
    local line_count
    line_count=$(echo "$response" | wc -l | tr -d ' ')
    
    local http_code
    http_code=$(echo "$response" | sed -n "$((line_count - 1))p")
    
    local time_total
    time_total=$(echo "$response" | tail -n1)
    
    local body
    body=$(echo "$response" | head -n $((line_count - 2)))
    
    local region="unknown"
    if echo "$body" | grep -q '"x-ms-region"'; then
        region=$(echo "$body" | grep -o '"x-ms-region":"[^"]*"' | cut -d'"' -f4)
    fi
    
    echo "$http_code|$time_total|$region"
}

# ============================================================================
# Test Functions
# ============================================================================

test_connectivity() {
    print_header "TEST 1: Connectivity Check"
    
    local endpoint="${FRONT_DOOR_ENDPOINT:-$APIM_ENDPOINT}"
    local endpoint_name=$([[ -n "$FRONT_DOOR_ENDPOINT" ]] && echo "Front Door" || echo "APIM")
    
    print_status "Testing connectivity via $endpoint_name..."
    
    for model in "gpt-4o" "gpt-4o-mini"; do
        print_status "Testing $model..."
        
        local response
        response=$(send_request "$endpoint" "$model" "Say OK" 5)
        
        local http_code
        http_code=$(echo "$response" | tail -n2 | head -n1)
        
        local body
        body=$(echo "$response" | head_except_last 2)
        
        if [[ "$http_code" == "200" ]]; then
            local content
            content=$(echo "$body" | jq -r '.choices[0].message.content // "N/A"' 2>/dev/null || echo "N/A")
            local region
            region=$(echo "$body" | jq -r '.model // "N/A"' 2>/dev/null || echo "N/A")
            print_success "$model: HTTP $http_code - Response: '$content'"
        else
            print_error "$model: HTTP $http_code"
            echo "$body" | jq '.' 2>/dev/null || echo "$body"
            return 1
        fi
    done
    
    echo ""
    print_success "All endpoints are accessible!"
    return 0
}

test_region_routing() {
    print_header "TEST 2: Region Routing Verification"
    
    local endpoint="${FRONT_DOOR_ENDPOINT:-$APIM_ENDPOINT}"
    
    print_status "Sending requests to verify which region is serving traffic..."
    print_status "Checking x-ms-region header from Azure OpenAI responses..."
    echo ""
    
    declare -A region_counts
    local total=10
    
    for i in $(seq 1 $total); do
        local response
        response=$(curl -s -i -X POST "${endpoint}/openai/deployments/gpt-4o/chat/completions?api-version=2024-08-01-preview" \
            -H "Content-Type: application/json" \
            -H "api-key: $APIM_SUBSCRIPTION_KEY" \
            -d '{"messages": [{"role": "user", "content": "OK"}], "max_tokens": 5}' 2>/dev/null)
        
        local region
        region=$(echo "$response" | grep -i "x-ms-region:" | sed 's/.*x-ms-region: *//' | tr -d '\r')
        
        if [[ -n "$region" ]]; then
            region_counts["$region"]=$((${region_counts["$region"]:-0} + 1))
            echo -e "  Request $i: ${GREEN}$region${NC}"
        else
            echo -e "  Request $i: ${YELLOW}Region unknown${NC}"
        fi
    done
    
    echo ""
    print_metric "Region Distribution:"
    for region in "${!region_counts[@]}"; do
        local count=${region_counts[$region]}
        local pct=$((count * 100 / total))
        echo "  $region: $count requests ($pct%)"
    done
    
    echo ""
    print_success "Region routing verification complete!"
}

test_burst_load() {
    print_header "TEST 3: Burst Load Test (Capacity Spillover)"
    
    local endpoint="${FRONT_DOOR_ENDPOINT:-$APIM_ENDPOINT}"
    local model="${1:-gpt-4o}"
    local burst_size="${2:-$BURST_SIZE}"
    
    print_status "Testing capacity spillover with burst load"
    print_status "Model: $model"
    print_status "Burst size: $burst_size parallel requests"
    print_status "Max tokens per request: $MAX_TOKENS"
    echo ""
    
    print_status "Architecture under test:"
    echo "  ┌─────────────────────────────────────────────────────────┐"
    echo "  │  Request → APIM Backend Pool                            │"
    echo "  │           ├─ Primary (Priority 1): 10K TPM capacity    │"
    echo "  │           └─ Spillover (Priority 2): 80K TPM capacity  │"
    echo "  │                                                         │"
    echo "  │  Circuit Breaker: Activates after 3x 429 errors        │"
    echo "  │  Expected: Primary handles load, spillover if needed   │"
    echo "  └─────────────────────────────────────────────────────────┘"
    echo ""
    
    # Create temp directory for results
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    print_status "Sending $burst_size parallel requests..."
    
    # Send parallel requests
    for i in $(seq 1 "$burst_size"); do
        curl -s -o "$temp_dir/response_$i.json" -w "%{http_code}" \
            -X POST "${endpoint}/openai/deployments/${model}/chat/completions?api-version=2024-08-01-preview" \
            -H "Content-Type: application/json" \
            -H "api-key: $APIM_SUBSCRIPTION_KEY" \
            -d "{\"messages\": [{\"role\": \"user\", \"content\": \"Write about cloud computing\"}], \"max_tokens\": $MAX_TOKENS}" \
            > "$temp_dir/status_$i.txt" 2>&1 &
    done
    
    # Wait for all requests
    wait
    
    # Analyze results
    local success=0
    local rate_limited=0
    local errors=0
    local total_tokens=0
    
    for i in $(seq 1 "$burst_size"); do
        local status
        status=$(cat "$temp_dir/status_$i.txt" 2>/dev/null || echo "000")
        
        case "$status" in
            200)
                ((success++)) || true
                local tokens
                tokens=$(jq -r '.usage.total_tokens // 0' "$temp_dir/response_$i.json" 2>/dev/null || echo 0)
                total_tokens=$((total_tokens + tokens))
                ;;
            429)
                ((rate_limited++)) || true
                ;;
            *)
                ((errors++)) || true
                ;;
        esac
    done
    
    echo ""
    print_metric "Results Summary:"
    echo "  ├─ Total Requests:  $burst_size"
    echo "  ├─ Successful (200): $success"
    echo "  ├─ Rate Limited (429): $rate_limited"
    echo "  ├─ Errors: $errors"
    echo "  └─ Total Tokens Used: $total_tokens"
    echo ""
    
    # Interpret results
    if [[ $success -eq $burst_size ]]; then
        print_success "All requests successful!"
        print_status "The backend pool handled the load within capacity limits."
        print_status "To trigger spillover, try: BURST_SIZE=100 MAX_TOKENS=1000 $0 burst"
    elif [[ $rate_limited -gt 0 ]] && [[ $success -gt 0 ]]; then
        print_warning "Rate limiting detected ($rate_limited requests got 429)"
        if [[ $success -gt $rate_limited ]]; then
            print_success "Circuit breaker likely activated - requests succeeded after initial 429s!"
            print_success "This indicates spillover to secondary backend is working."
        fi
    elif [[ $rate_limited -eq $burst_size ]]; then
        print_error "All requests were rate limited!"
        print_status "Both primary and spillover backends may be at capacity."
    else
        print_warning "Mixed results - review individual responses for details."
    fi
}

test_sustained_load() {
    print_header "TEST 4: Sustained Load Test"
    
    local endpoint="${FRONT_DOOR_ENDPOINT:-$APIM_ENDPOINT}"
    local model="${1:-gpt-4o}"
    local duration="${2:-60}"
    
    print_status "Running sustained load test"
    print_status "Model: $model"
    print_status "Duration: ${duration} seconds"
    print_status "Purpose: Observe circuit breaker behavior over time"
    echo ""
    
    local results_file="spillover-test-$(date +%Y%m%d-%H%M%S).csv"
    echo "timestamp,request_id,http_code,response_time_ms,tokens" > "$results_file"
    
    local start_time
    start_time=$(date +%s)
    local end_time=$((start_time + duration))
    local request_id=0
    local success=0
    local rate_limited=0
    
    print_status "Starting sustained requests (Ctrl+C to stop early)..."
    echo ""
    
    while [[ $(date +%s) -lt $end_time ]]; do
        ((request_id++)) || true
        
        local timestamp
        timestamp=$(date +%s.%N)
        
        local response
        response=$(curl -s -w "\n%{http_code}\n%{time_total}" \
            -X POST "${endpoint}/openai/deployments/${model}/chat/completions?api-version=2024-08-01-preview" \
            -H "Content-Type: application/json" \
            -H "api-key: $APIM_SUBSCRIPTION_KEY" \
            -d '{"messages": [{"role": "user", "content": "Hello"}], "max_tokens": 10}' 2>/dev/null)
        
        local http_code
        http_code=$(echo "$response" | tail -n2 | head -n1)
        
        local time_ms
        time_ms=$(echo "$response" | tail -n1 | awk '{printf "%.0f", $1 * 1000}')
        
        local tokens=0
        if [[ "$http_code" == "200" ]]; then
            ((success++))
            tokens=$(echo "$response" | head_except_last 2 | jq -r '.usage.total_tokens // 0' 2>/dev/null || echo 0)
        elif [[ "$http_code" == "429" ]]; then
            ((rate_limited++)) || true
        fi
        
        echo "$timestamp,$request_id,$http_code,$time_ms,$tokens" >> "$results_file"
        
        local remaining=$((end_time - $(date +%s)))
        printf "\r  Requests: %d | Success: %d | Rate Limited: %d | Remaining: %ds   " \
            "$request_id" "$success" "$rate_limited" "$remaining"
        
        # Small delay to avoid overwhelming
        sleep 0.1
    done
    
    echo ""
    echo ""
    
    print_metric "Final Results:"
    echo "  Total Requests: $request_id"
    echo "  Successful: $success ($((success * 100 / request_id))%)"
    echo "  Rate Limited: $rate_limited ($((rate_limited * 100 / request_id))%)"
    echo ""
    print_status "Results saved to: $results_file"
    
    if [[ $rate_limited -gt 0 ]]; then
        print_warning "Rate limiting occurred - circuit breaker may have been triggered"
    else
        print_success "No rate limiting - capacity was sufficient for this load"
    fi
}

# ============================================================================
# Main
# ============================================================================

show_help() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  connectivity         Test basic API connectivity"
    echo "  region              Verify which region is serving requests"
    echo "  burst [model]       Send burst of parallel requests (default: gpt-4o)"
    echo "  sustained [model] [duration]  Sustained load test (default: gpt-4o, 60s)"
    echo "  all                 Run all tests in sequence"
    echo "  help                Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  APIM_SUBSCRIPTION_KEY   Required: API subscription key from APIM"
    echo "  FRONT_DOOR_ENDPOINT     Optional: Front Door URL (auto-discovered)"
    echo "  APIM_ENDPOINT           Optional: Direct APIM URL (auto-discovered)"
    echo "  DEPLOYMENT_NAME         Optional: Bicep deployment name (default: apim-aoai-multi-region)"
    echo "  BURST_SIZE              Optional: Number of parallel requests (default: 30)"
    echo "  MAX_TOKENS              Optional: Max tokens per request (default: 500)"
    echo ""
    echo "Examples:"
    echo "  export APIM_SUBSCRIPTION_KEY='your-key-here'"
    echo "  $0 connectivity              # Test basic connectivity"
    echo "  $0 burst gpt-4o              # Burst test with gpt-4o"
    echo "  $0 sustained gpt-4o 120      # 2-minute sustained test"
    echo "  BURST_SIZE=50 $0 burst       # Larger burst test"
}

main() {
    local command="${1:-help}"
    
    case "$command" in
        connectivity|connect)
            discover_config
            test_connectivity
            ;;
        region|routing)
            discover_config
            test_region_routing
            ;;
        burst|load)
            discover_config
            test_burst_load "${2:-gpt-4o}" "${3:-$BURST_SIZE}"
            ;;
        sustained|stress)
            discover_config
            test_sustained_load "${2:-gpt-4o}" "${3:-60}"
            ;;
        all|full)
            discover_config
            test_connectivity
            test_region_routing
            test_burst_load "${2:-gpt-4o}"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
