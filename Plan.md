# Multi-Region Azure APIM + AOAI Architecture Implementation Plan

## Overview

Implement a highly available Azure architecture with:
- **Azure Front Door (AFD)** as global entry point
- **Azure API Management (APIM)** in two regions with backend pools
- **Azure OpenAI (AOAI)** with PTU + Pay-as-you-go spillover in each region

## Architecture Diagram Summary

```
                    ┌─────────────────┐
                    │  Azure Front    │
                    │     Door        │
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            │                                 │
            ▼                                 ▼
┌───────────────────────┐       ┌───────────────────────┐
│   APIM East US        │       │   APIM West US        │
│  ┌─────────────────┐  │       │  ┌─────────────────┐  │
│  │ GPT-4.1 Endpoint│  │       │  │ GPT-4.1 Endpoint│  │
│  │ GPT-4.1-mini EP │  │       │  │ GPT-4.1-mini EP │  │
│  └─────────────────┘  │       │  └─────────────────┘  │
└───────────┬───────────┘       └───────────┬───────────┘
            │                               │
    ┌───────┴───────┐               ┌───────┴───────┐
    │               │               │               │
    ▼               ▼               ▼               ▼
┌───────┐     ┌───────┐       ┌───────┐     ┌───────┐
│ PTU   │────▶│ PAYG  │       │ PTU   │────▶│ PAYG  │
│(East) │spill│(East) │       │(West) │spill│(West) │
└───────┘     └───────┘       └───────┘     └───────┘
```

## Implementation Steps

### Step 1: Create Bicep Folder Structure
- `main.bicep` - Main orchestration file
- `main.bicepparam` - Parameters file
- `bicepconfig.json` - Bicep configuration
- `modules/` - Reusable modules
  - `aoai/aoai.bicep` - Azure OpenAI with deployments
  - `apim/apim.bicep` - API Management with backends
  - `frontdoor/frontdoor.bicep` - Azure Front Door
- `scripts/deploy.sh` - Deployment automation
- `tests/` - Test scripts for failover scenarios

### Step 2: Implement Azure OpenAI Module
- Create OpenAI accounts in East US and West US
- Deploy models with PTU (small ~25-50 units for testing exhaustion)
- Deploy models with Pay-as-you-go (spillover)
- Models: `gpt-4o` and `gpt-4o-mini` (widely available)

### Step 3: Implement APIM Module
- Premium tier for multi-region capability
- Backend pools with circuit breaker
- Priority-based routing: PTU (priority 1) → PAYG (priority 2)
- 429 handling for automatic spillover

### Step 4: Implement Azure Front Door Module
- Premium SKU for Private Link support
- Health probes for APIM endpoints
- Active-active routing with latency-based failover
- Origin groups for each APIM region

### Step 5: Create Deployment Orchestration
- Wire up main.bicep with correct dependencies
- AOAI → APIM → Front Door deployment order
- Parameter file for environment configuration

### Step 6: Deploy to Azure
- Use Azure CLI for deployment
- Target subscription and resource groups
- Monitor deployment progress

### Step 7: Verify and Iterate
- Check all resources deployed successfully
- Fix any errors and redeploy
- Handle regional capacity issues by switching regions

### Step 8: Create Test Cases
1. **Region Failover Test**: Disable East US APIM backend, verify traffic routes to West US
2. **PTU Exhaustion Test**: Send high-volume requests to exhaust small PTU allocation, verify spillover to PAYG

## Resource Configuration

| Resource | SKU | Regions | Notes |
|----------|-----|---------|-------|
| Azure Front Door | Premium | Global | Required for Private Link |
| API Management | Premium | East US, West US | Multi-region requires Premium |
| Azure OpenAI | S0 | East US, West US | 2 accounts per region (PTU + PAYG) |

## Model Deployments

| Model | Deployment Type | Capacity | Purpose |
|-------|-----------------|----------|---------|
| gpt-4o | PTU | 25 units | Primary, small for exhaustion testing |
| gpt-4o | Standard | 120K TPM | Spillover |
| gpt-4o-mini | PTU | 25 units | Primary, small for exhaustion testing |
| gpt-4o-mini | Standard | 120K TPM | Spillover |

## Estimated Costs (Monthly)

| Resource | Estimated Cost |
|----------|----------------|
| APIM Premium (2 units) | ~$5,600 |
| AFD Premium | ~$35 + usage |
| AOAI PTU (100 units total) | Variable |
| AOAI Standard | Pay-per-use |

## Test Scenarios

### Test 1: Region Failover
1. Baseline: Verify requests route to nearest region
2. Disable East US APIM backend
3. Verify AFD health probe fails
4. Verify all traffic routes to West US
5. Re-enable East US, verify traffic rebalances

### Test 2: PTU Exhaustion → PAYG Spillover
1. Configure PTU with minimal capacity (25 units)
2. Send concurrent requests exceeding PTU capacity
3. Monitor for 429 responses triggering circuit breaker
4. Verify subsequent requests route to PAYG deployment
5. Verify seamless user experience (no errors visible)

## Files to Create

```
azure-apim-aoai-multi-region/
├── Plan.md                      # This file
├── README.md                    # Project documentation
├── main.bicep                   # Main deployment
├── main.bicepparam.example      # Parameters template (copy to main.bicepparam)
├── bicepconfig.json             # Bicep config
├── .gitignore                   # Git ignore rules
├── modules/
│   ├── aoai/
│   │   └── aoai.bicep           # Azure OpenAI module
│   ├── apim/
│   │   └── apim.bicep           # APIM module with policies
│   ├── frontdoor/
│   │   └── frontdoor.bicep      # Front Door module
│   └── rbac/
│       └── cognitive-services-user.bicep  # RBAC assignments
├── scripts/
│   └── deploy.sh                # Deployment script
└── tests/
    ├── test-region-failover.sh  # Region failover test
    └── test-ptu-spillover.sh    # Capacity spillover test
```
