#!/bin/bash
# ============================================================================
# Deployment Script for Multi-Region Azure APIM + AOAI Architecture
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - can be overridden via environment variables
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-apim-aoai-multi-region}"
LOCATION="${LOCATION:-eastus}"
BICEP_FILE="main.bicep"
PARAMS_FILE="main.bicepparam"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if logged into Azure
check_azure_login() {
    print_status "Checking Azure CLI login status..."
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    print_success "Logged into subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
}

# Validate Bicep templates
validate_templates() {
    print_status "Validating Bicep templates..."
    
    if ! az bicep build --file "$BICEP_FILE" --stdout > /dev/null 2>&1; then
        print_error "Bicep validation failed. Running with verbose output..."
        az bicep build --file "$BICEP_FILE"
        exit 1
    fi
    
    print_success "Bicep templates are valid"
}

# Run what-if deployment
run_whatif() {
    print_status "Running what-if deployment..."
    
    az deployment sub what-if \
        --name "$DEPLOYMENT_NAME" \
        --location "$LOCATION" \
        --template-file "$BICEP_FILE" \
        --parameters "$PARAMS_FILE"
    
    print_success "What-if complete"
}

# Deploy the infrastructure
deploy() {
    print_status "Starting deployment..."
    print_warning "This deployment may take 30-45 minutes (APIM Premium deployment is slow)"
    
    az deployment sub create \
        --name "$DEPLOYMENT_NAME" \
        --location "$LOCATION" \
        --template-file "$BICEP_FILE" \
        --parameters "$PARAMS_FILE" \
        --verbose
    
    print_success "Deployment complete!"
}

# Get deployment outputs
get_outputs() {
    print_status "Retrieving deployment outputs..."
    
    az deployment sub show \
        --name "$DEPLOYMENT_NAME" \
        --query properties.outputs \
        -o json
}

# Verify deployment
verify_deployment() {
    print_status "Verifying deployment..."
    
    # Get resource group name from deployment
    RG_NAME=$(az deployment sub show \
        --name "$DEPLOYMENT_NAME" \
        --query properties.outputs.resourceGroupName.value \
        -o tsv)
    
    print_status "Checking resources in resource group: $RG_NAME"
    
    # List all resources
    az resource list \
        --resource-group "$RG_NAME" \
        --output table
    
    print_success "Verification complete"
}

# Delete deployment (cleanup)
cleanup() {
    print_warning "This will delete all deployed resources!"
    read -p "Are you sure you want to delete? (y/N) " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        RG_NAME=$(az deployment sub show \
            --name "$DEPLOYMENT_NAME" \
            --query properties.outputs.resourceGroupName.value \
            -o tsv 2>/dev/null || echo "")
        
        if [ -n "$RG_NAME" ]; then
            print_status "Deleting resource group: $RG_NAME"
            az group delete --name "$RG_NAME" --yes --no-wait
            print_success "Resource group deletion initiated"
        else
            print_error "Could not find resource group to delete"
        fi
    else
        print_status "Cleanup cancelled"
    fi
}

# Show help
show_help() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  validate    Validate Bicep templates"
    echo "  whatif      Run what-if deployment (preview changes)"
    echo "  deploy      Deploy the infrastructure"
    echo "  outputs     Get deployment outputs"
    echo "  verify      Verify deployed resources"
    echo "  cleanup     Delete all deployed resources"
    echo "  help        Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 validate   # Validate templates"
    echo "  $0 whatif     # Preview changes"
    echo "  $0 deploy     # Deploy to Azure"
}

# Main script
main() {
    # Navigate to script directory
    cd "$(dirname "$0")/.."
    
    case "${1:-help}" in
        validate)
            check_azure_login
            validate_templates
            ;;
        whatif)
            check_azure_login
            validate_templates
            run_whatif
            ;;
        deploy)
            check_azure_login
            validate_templates
            deploy
            get_outputs
            ;;
        outputs)
            check_azure_login
            get_outputs
            ;;
        verify)
            check_azure_login
            verify_deployment
            ;;
        cleanup)
            check_azure_login
            cleanup
            ;;
        help|*)
            show_help
            ;;
    esac
}

main "$@"
