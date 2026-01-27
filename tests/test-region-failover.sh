#!/usr/bin/env bash
# ============================================================================
# Test Script: Region Failover
#
# Tests Azure Front Door's ability to failover between regions when the
# primary APIM origin becomes unavailable.
#
# Architecture:
#   Client → Front Door → APIM (East US) ←→ AOAI (East US)
#                      → APIM (West US) ←→ AOAI (West US)
#
# Test Scenarios:
#   1. Baseline: Verify both regions are healthy
#   2. Failover: Disable primary, verify traffic routes to secondary
#   3. Recovery: Re-enable primary, verify load balancing resumes
#
# Prerequisites:
#   - Azure CLI logged in with sufficient permissions
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

# Deployment configuration (can be overridden via environment variables)
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-apim-aoai-multi-region}"
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
FRONT_DOOR_NAME="${FRONT_DOOR_NAME:-}"
FRONT_DOOR_ENDPOINT="${FRONT_DOOR_ENDPOINT:-}"
APIM_SUBSCRIPTION_KEY="${APIM_SUBSCRIPTION_KEY:-}"

# Test parameters
REQUEST_COUNT="${REQUEST_COUNT:-10}"
SUCCESS_THRESHOLD="${SUCCESS_THRESHOLD:-80}"  # Percentage
HEALTH_PROBE_WAIT="${HEALTH_PROBE_WAIT:-60}"  # Seconds to wait for health probe detection

# ============================================================================
# Helper Functions
# ============================================================================

print_header()  { echo -e "\n${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"; echo -e "${BOLD}${BLUE}  $1${NC}"; echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}\n"; }
print_status()  { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
print_metric()  { echo -e "${CYAN}[DATA]${NC} $1"; }

# ============================================================================
# Configuration Discovery
# ============================================================================

discover_config() {
    print_status "Discovering deployment configuration..."
    
    # Try to get values from deployment outputs
    if [[ -z "$FRONT_DOOR_ENDPOINT" ]]; then
        FRONT_DOOR_ENDPOINT=$(az deployment sub show \
            --name "$DEPLOYMENT_NAME" \
            --query "properties.outputs.frontDoorEndpointUrl.value" \
            -o tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        RESOURCE_GROUP=$(az deployment sub show \
            --name "$DEPLOYMENT_NAME" \
            --query "properties.outputs.resourceGroupName.value" \
            -o tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "$FRONT_DOOR_NAME" ]]; then
        FRONT_DOOR_NAME=$(az deployment sub show \
            --name "$DEPLOYMENT_NAME" \
            --query "properties.outputs.frontDoorName.value" \
            -o tsv 2>/dev/null || echo "")
    fi
    
    # Validate required configuration
    local missing=()
    [[ -z "$FRONT_DOOR_ENDPOINT" ]] && missing+=("FRONT_DOOR_ENDPOINT")
    [[ -z "$APIM_SUBSCRIPTION_KEY" ]] && missing+=("APIM_SUBSCRIPTION_KEY")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required configuration: ${missing[*]}"
        echo ""
        echo "Set the following environment variables:"
        for var in "${missing[@]}"; do
            echo "  export $var='your-value'"
        done
        exit 1
    fi
    
    # Optional: Resource group and Front Door name (needed for origin manipulation)
    if [[ -z "$RESOURCE_GROUP" ]] || [[ -z "$FRONT_DOOR_NAME" ]]; then
        print_warning "RESOURCE_GROUP and FRONT_DOOR_NAME not set."
        print_warning "Failover simulation (origin disable/enable) will not be available."
        print_warning "Only read-only tests will run."
    fi
    
    echo ""
    print_success "Configuration:"
    echo "  Front Door Endpoint: $FRONT_DOOR_ENDPOINT"
    [[ -n "$RESOURCE_GROUP" ]] && echo "  Resource Group: $RESOURCE_GROUP"
    [[ -n "$FRONT_DOOR_NAME" ]] && echo "  Front Door Name: $FRONT_DOOR_NAME"
    echo ""
}

# ============================================================================
# API Request Functions
# ============================================================================

# Send a single test request
send_test_request() {
    local endpoint="$1"
    local model="${2:-gpt-4o}"
    
    curl -s -w "\n%{http_code}" \
        -X POST "${endpoint}/openai/deployments/${model}/chat/completions?api-version=2024-08-01-preview" \
        -H "Content-Type: application/json" \
        -H "api-key: $APIM_SUBSCRIPTION_KEY" \
        -d '{"messages": [{"role": "user", "content": "Say hello"}], "max_tokens": 10}' \
        2>/dev/null
}

# Send request with full headers (for region detection)
send_request_with_headers() {
    local endpoint="$1"
    local model="${2:-gpt-4o}"
    
    curl -s -i -X POST "${endpoint}/openai/deployments/${model}/chat/completions?api-version=2024-08-01-preview" \
        -H "Content-Type: application/json" \
        -H "api-key: $APIM_SUBSCRIPTION_KEY" \
        -d '{"messages": [{"role": "user", "content": "OK"}], "max_tokens": 5}' \
        2>/dev/null
}

# ============================================================================
# Test Functions
# ============================================================================

test_baseline() {
    print_header "TEST: Baseline Health Check"
    
    print_status "Verifying all regions are healthy and responding..."
    print_status "Sending $REQUEST_COUNT requests..."
    echo ""
    
    local success=0
    local failed=0
    declare -A regions
    
    for i in $(seq 1 "$REQUEST_COUNT"); do
        local response
        response=$(send_request_with_headers "$FRONT_DOOR_ENDPOINT")
        
        local http_code
        http_code=$(echo "$response" | grep "^HTTP" | tail -1 | awk '{print $2}')
        
        local region
        region=$(echo "$response" | grep -i "x-ms-region:" | sed 's/.*x-ms-region: *//' | tr -d '\r' || echo "unknown")
        
        if [[ "$http_code" == "200" ]]; then
            ((success++)) || true
            regions["$region"]=$((${regions["$region"]:-0} + 1))
            echo -e "  Request $i: ${GREEN}HTTP $http_code${NC} - Region: $region"
        else
            ((failed++)) || true
            echo -e "  Request $i: ${RED}HTTP ${http_code:-error}${NC}"
        fi
        
        sleep 0.5
    done
    
    echo ""
    print_metric "Results:"
    echo "  Successful: $success / $REQUEST_COUNT"
    echo "  Failed: $failed / $REQUEST_COUNT"
    
    if [[ ${#regions[@]} -gt 0 ]]; then
        echo ""
        print_metric "Region Distribution:"
        for region in "${!regions[@]}"; do
            echo "  $region: ${regions[$region]} requests"
        done
    fi
    
    local success_pct=$((success * 100 / REQUEST_COUNT))
    echo ""
    
    if [[ $success_pct -ge $SUCCESS_THRESHOLD ]]; then
        print_success "Baseline test PASSED ($success_pct% success rate)"
        return 0
    else
        print_error "Baseline test FAILED ($success_pct% success rate, threshold: $SUCCESS_THRESHOLD%)"
        return 1
    fi
}

test_region_consistency() {
    print_header "TEST: Region Consistency"
    
    print_status "Checking if requests are consistently routed..."
    echo ""
    
    declare -A region_counts
    local total=20
    
    for i in $(seq 1 $total); do
        local response
        response=$(send_request_with_headers "$FRONT_DOOR_ENDPOINT")
        
        local region
        region=$(echo "$response" | grep -i "x-ms-region:" | sed 's/.*x-ms-region: *//' | tr -d '\r')
        
        if [[ -n "$region" ]]; then
            region_counts["$region"]=$((${region_counts["$region"]:-0} + 1))
        fi
        
        printf "\r  Progress: %d/%d requests..." "$i" "$total"
    done
    
    echo ""
    echo ""
    
    print_metric "Region Distribution:"
    for region in "${!region_counts[@]}"; do
        local count=${region_counts[$region]}
        local pct=$((count * 100 / total))
        echo "  $region: $count requests ($pct%)"
    done
    
    echo ""
    print_success "Region consistency test complete"
}

simulate_region_failure() {
    print_header "TEST: Simulated Region Failure"
    
    if [[ -z "$RESOURCE_GROUP" ]] || [[ -z "$FRONT_DOOR_NAME" ]]; then
        print_warning "Cannot simulate failure: RESOURCE_GROUP and FRONT_DOOR_NAME required"
        print_status "Set these environment variables to enable this test"
        return 1
    fi
    
    print_status "This test will:"
    echo "  1. Disable the primary origin (simulating region failure)"
    echo "  2. Wait for Front Door health probes to detect the failure"
    echo "  3. Verify traffic routes to the secondary region"
    echo "  4. Re-enable the primary origin"
    echo "  5. Verify traffic resumes to both regions"
    echo ""
    
    print_warning "This will temporarily impact your Front Door configuration!"
    read -p "Continue? (y/N) " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Test cancelled"
        return 0
    fi
    
    # Get origin group name
    local origin_group
    origin_group=$(az afd origin-group list \
        --resource-group "$RESOURCE_GROUP" \
        --profile-name "$FRONT_DOOR_NAME" \
        --query "[0].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$origin_group" ]]; then
        print_error "Could not find origin group"
        return 1
    fi
    
    # Get primary origin name (assuming it's the first one or contains 'east')
    local primary_origin
    primary_origin=$(az afd origin list \
        --resource-group "$RESOURCE_GROUP" \
        --profile-name "$FRONT_DOOR_NAME" \
        --origin-group-name "$origin_group" \
        --query "[?contains(name, 'east') || contains(name, 'primary')].name | [0]" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$primary_origin" ]]; then
        # Fallback: get first origin
        primary_origin=$(az afd origin list \
            --resource-group "$RESOURCE_GROUP" \
            --profile-name "$FRONT_DOOR_NAME" \
            --origin-group-name "$origin_group" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi
    
    if [[ -z "$primary_origin" ]]; then
        print_error "Could not find primary origin to disable"
        return 1
    fi
    
    print_status "Origin Group: $origin_group"
    print_status "Primary Origin: $primary_origin"
    echo ""
    
    # Step 1: Disable primary origin
    print_status "Step 1: Disabling primary origin..."
    az afd origin update \
        --resource-group "$RESOURCE_GROUP" \
        --profile-name "$FRONT_DOOR_NAME" \
        --origin-group-name "$origin_group" \
        --origin-name "$primary_origin" \
        --enabled-state "Disabled" \
        --output none
    
    print_success "Primary origin disabled"
    
    # Step 2: Wait for health probe
    print_status "Step 2: Waiting ${HEALTH_PROBE_WAIT}s for health probes to detect failure..."
    for i in $(seq "$HEALTH_PROBE_WAIT" -1 1); do
        printf "\r  Waiting: %ds remaining...  " "$i"
        sleep 1
    done
    echo ""
    
    # Step 3: Test failover
    print_status "Step 3: Testing failover..."
    local failover_success=0
    
    for i in $(seq 1 "$REQUEST_COUNT"); do
        local response
        response=$(send_test_request "$FRONT_DOOR_ENDPOINT")
        
        local http_code
        http_code=$(echo "$response" | tail -n1)
        
        if [[ "$http_code" == "200" ]]; then
            ((failover_success++)) || true
        fi
        
        printf "\r  Failover test: %d/%d requests (success: %d)..." "$i" "$REQUEST_COUNT" "$failover_success"
    done
    echo ""
    
    local failover_pct=$((failover_success * 100 / REQUEST_COUNT))
    
    if [[ $failover_pct -ge $SUCCESS_THRESHOLD ]]; then
        print_success "Failover test PASSED ($failover_pct% success during failover)"
    else
        print_error "Failover test FAILED ($failover_pct% success during failover)"
    fi
    
    # Step 4: Re-enable primary
    print_status "Step 4: Re-enabling primary origin..."
    az afd origin update \
        --resource-group "$RESOURCE_GROUP" \
        --profile-name "$FRONT_DOOR_NAME" \
        --origin-group-name "$origin_group" \
        --origin-name "$primary_origin" \
        --enabled-state "Enabled" \
        --output none
    
    print_success "Primary origin re-enabled"
    
    # Step 5: Wait and test recovery
    print_status "Step 5: Waiting ${HEALTH_PROBE_WAIT}s for recovery..."
    for i in $(seq "$HEALTH_PROBE_WAIT" -1 1); do
        printf "\r  Waiting: %ds remaining...  " "$i"
        sleep 1
    done
    echo ""
    
    print_status "Step 6: Testing recovery..."
    local recovery_success=0
    
    for i in $(seq 1 "$REQUEST_COUNT"); do
        local response
        response=$(send_test_request "$FRONT_DOOR_ENDPOINT")
        
        local http_code
        http_code=$(echo "$response" | tail -n1)
        
        if [[ "$http_code" == "200" ]]; then
            ((recovery_success++)) || true
        fi
        
        printf "\r  Recovery test: %d/%d requests (success: %d)..." "$i" "$REQUEST_COUNT" "$recovery_success"
    done
    echo ""
    
    local recovery_pct=$((recovery_success * 100 / REQUEST_COUNT))
    
    if [[ $recovery_pct -ge $SUCCESS_THRESHOLD ]]; then
        print_success "Recovery test PASSED ($recovery_pct% success after recovery)"
    else
        print_error "Recovery test FAILED ($recovery_pct% success after recovery)"
    fi
    
    echo ""
    print_header "REGION FAILOVER TEST SUMMARY"
    echo "  Failover Success Rate: $failover_pct%"
    echo "  Recovery Success Rate: $recovery_pct%"
    
    if [[ $failover_pct -ge $SUCCESS_THRESHOLD ]] && [[ $recovery_pct -ge $SUCCESS_THRESHOLD ]]; then
        print_success "Overall: PASSED - Region failover working correctly!"
    else
        print_error "Overall: FAILED - Review the results above"
    fi
}

test_front_door_status() {
    print_header "TEST: Front Door Health Status"
    
    if [[ -z "$RESOURCE_GROUP" ]] || [[ -z "$FRONT_DOOR_NAME" ]]; then
        print_warning "Cannot check status: RESOURCE_GROUP and FRONT_DOOR_NAME required"
        return 1
    fi
    
    print_status "Checking Front Door endpoint status..."
    
    local endpoint_info
    endpoint_info=$(az afd endpoint list \
        --resource-group "$RESOURCE_GROUP" \
        --profile-name "$FRONT_DOOR_NAME" \
        --query "[0].{name: name, hostName: hostName, enabledState: enabledState, deploymentStatus: deploymentStatus}" \
        -o json 2>/dev/null)
    
    if [[ -n "$endpoint_info" ]]; then
        echo "$endpoint_info" | jq '.'
    fi
    
    echo ""
    print_status "Checking origin group health..."
    
    local origin_groups
    origin_groups=$(az afd origin-group list \
        --resource-group "$RESOURCE_GROUP" \
        --profile-name "$FRONT_DOOR_NAME" \
        --query "[].name" -o tsv 2>/dev/null)
    
    for og in $origin_groups; do
        echo ""
        print_metric "Origin Group: $og"
        
        az afd origin list \
            --resource-group "$RESOURCE_GROUP" \
            --profile-name "$FRONT_DOOR_NAME" \
            --origin-group-name "$og" \
            --query "[].{name: name, hostName: hostName, enabled: enabledState, priority: priority, weight: weight}" \
            -o table 2>/dev/null
    done
}

# ============================================================================
# Main
# ============================================================================

show_help() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  baseline            Test that Front Door is healthy and routing correctly"
    echo "  consistency         Check region routing consistency"
    echo "  status              Show Front Door and origin health status"
    echo "  failover            Simulate region failure and test failover (requires permissions)"
    echo "  all                 Run all read-only tests (baseline + consistency + status)"
    echo "  help                Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  APIM_SUBSCRIPTION_KEY   Required: API subscription key from APIM"
    echo "  FRONT_DOOR_ENDPOINT     Optional: Front Door URL (auto-discovered)"
    echo "  RESOURCE_GROUP          Optional: Resource group name (for origin manipulation)"
    echo "  FRONT_DOOR_NAME         Optional: Front Door profile name (for origin manipulation)"
    echo "  DEPLOYMENT_NAME         Optional: Bicep deployment name (default: apim-aoai-multi-region)"
    echo "  REQUEST_COUNT           Optional: Number of test requests (default: 10)"
    echo "  SUCCESS_THRESHOLD       Optional: Success percentage threshold (default: 80)"
    echo "  HEALTH_PROBE_WAIT       Optional: Seconds to wait for health probes (default: 60)"
    echo ""
    echo "Examples:"
    echo "  export APIM_SUBSCRIPTION_KEY='your-key'"
    echo "  $0 baseline              # Basic health check"
    echo "  $0 consistency           # Check region routing"
    echo "  $0 status                # Show Front Door status"
    echo "  $0 failover              # Full failover test (destructive)"
    echo ""
    echo "Note: The 'failover' command requires Azure CLI permissions to modify"
    echo "      Front Door origins. Use with caution in production!"
}

main() {
    local command="${1:-help}"
    
    case "$command" in
        baseline|health)
            discover_config
            test_baseline
            ;;
        consistency|routing|region)
            discover_config
            test_region_consistency
            ;;
        status|info)
            discover_config
            test_front_door_status
            ;;
        failover|simulate)
            discover_config
            simulate_region_failure
            ;;
        all|full)
            discover_config
            test_baseline
            test_region_consistency
            test_front_door_status
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
