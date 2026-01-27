"# Multi-Region Azure APIM + Azure OpenAI Architecture

A production-ready Bicep template for deploying a highly available, multi-region Azure architecture with Azure Front Door, API Management, and Azure OpenAI.

## 🏗️ Architecture Overview

```
                    ┌─────────────────────────────────┐
                    │      Azure Front Door           │
                    │    (Global Load Balancer)       │
                    │         + WAF Policy            │
                    └────────────────┬────────────────┘
                                     │
                    ┌────────────────┴────────────────┐
                    │                                 │
                    ▼                                 ▼
        ┌───────────────────────┐       ┌───────────────────────┐
        │   APIM (East US)      │       │   APIM (West US)      │
        │   Backend Pool:       │       │   Backend Pool:       │
        │   ├─ Primary (P1)     │       │   ├─ Primary (P1)     │
        │   └─ Spillover (P2)   │       │   └─ Spillover (P2)   │
        └───────────┬───────────┘       └───────────┬───────────┘
                    │                               │
        ┌───────────┴───────────┐       ┌───────────┴───────────┐
        │                       │       │                       │
        ▼                       ▼       ▼                       ▼
   ┌─────────┐           ┌─────────┐   ┌─────────┐       ┌─────────┐
   │ Primary │  circuit  │Spillover│   │ Primary │circuit│Spillover│
   │  AOAI   │──breaker─▶│  AOAI   │   │  AOAI   │──────▶│  AOAI   │
   │(10K TPM)│           │(80K TPM)│   │(10K TPM)│       │(80K TPM)│
   └─────────┘           └─────────┘   └─────────┘       └─────────┘
      East US               East US       West US           West US
```

## ✨ Features

- **Global Load Balancing**: Azure Front Door Premium with latency-based routing
- **Multi-Region Resilience**: Automatic failover between East US and West US
- **Capacity Spillover**: Circuit breaker pattern for automatic failover from primary to spillover backends
- **Managed Identity Authentication**: Secure AOAI access without API keys in code
- **WAF Protection**: Web Application Firewall in detection mode
- **Infrastructure as Code**: Fully automated deployment with Bicep

## 📋 Prerequisites

- Azure subscription with Owner or Contributor access
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) v2.50+
- [Bicep CLI](https://docs.microsoft.com/azure/azure-resource-manager/bicep/install) v0.20+
- Azure OpenAI access (apply at https://aka.ms/oai/access)

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/azure-apim-aoai-multi-region.git
cd azure-apim-aoai-multi-region
```

### 2. Configure Parameters

```bash
# Copy the example parameters file
cp main.bicepparam.example main.bicepparam

# Edit with your values
# Required: baseName, apimPublisherEmail, apimPublisherName
```

### 3. Deploy

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "Your Subscription Name"

# Deploy (takes 30-45 minutes)
./scripts/deploy.sh deploy
```

### 4. Test the Deployment

```bash
# Get deployment outputs
./scripts/deploy.sh outputs

# Set environment variables for testing
export FRONT_DOOR_ENDPOINT="https://your-fd-endpoint.azurefd.net"
export APIM_SUBSCRIPTION_KEY="your-subscription-key"  # From Azure Portal

# Run tests
./tests/test-region-failover.sh
./tests/test-ptu-spillover.sh
```

## 📁 Project Structure

```
├── main.bicep                    # Main orchestration template
├── main.bicepparam.example       # Example parameters (copy to main.bicepparam)
├── bicepconfig.json              # Bicep configuration
├── modules/
│   ├── aoai/aoai.bicep           # Azure OpenAI deployments
│   ├── apim/apim.bicep           # API Management with policies
│   ├── frontdoor/frontdoor.bicep # Front Door configuration
│   └── rbac/cognitive-services-user.bicep
├── scripts/
│   └── deploy.sh                 # Deployment automation
└── tests/
    ├── test-capacity-spillover.sh  # Capacity spillover test
    └── test-region-failover.sh     # Region failover test
```

## ⚙️ Configuration

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `baseName` | Unique prefix for all resources | `contoso-aoai` |
| `apimPublisherEmail` | Email for APIM publisher | `admin@example.com` |
| `apimPublisherName` | Organization name | `Contoso` |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `primaryLocation` | `eastus` | Primary Azure region |
| `secondaryLocation` | `westus` | Secondary Azure region |
| `gpt4oPrimaryCapacity` | `10` | Primary GPT-4o capacity (TPM thousands) |
| `gpt4oSpilloverCapacity` | `80` | Spillover GPT-4o capacity |

## 🧪 Testing

### Prerequisites

```bash
# Get your APIM subscription key from Azure Portal
# Navigate to: APIM → Subscriptions → Built-in all-access subscription → Show/Hide keys
export APIM_SUBSCRIPTION_KEY="your-subscription-key"

# Set your deployment name (check with: az deployment sub list --query "[].name" -o table)
export DEPLOYMENT_NAME="your-deployment-name"

# Optional: Override auto-discovered endpoints
export FRONT_DOOR_ENDPOINT="https://your-fd-endpoint.azurefd.net"
export RESOURCE_GROUP="your-resource-group"
```

### Test 1: Capacity Spillover

Tests automatic failover when primary backend capacity is exhausted.

**How it works:**
1. Primary backend configured with low capacity (10K TPM)
2. Send burst of requests exceeding primary capacity
3. Circuit breaker activates after 3x 429 errors
4. Traffic automatically routes to spillover backend (80K TPM)

**Usage:**
```bash
cd tests

# Show help and available commands
./test-capacity-spillover.sh help

# Basic connectivity test
./test-capacity-spillover.sh baseline

# Verify region routing with priority
./test-capacity-spillover.sh routing

# Send burst requests to trigger spillover
./test-capacity-spillover.sh burst

# Sustained load test (longer duration)
./test-capacity-spillover.sh sustained

# Run all tests
./test-capacity-spillover.sh all
```

**Configuration Options:**
```bash
export REQUEST_COUNT=50        # Number of burst requests (default: 50)
export SUSTAINED_DURATION=60   # Duration in seconds (default: 60)
export SUCCESS_THRESHOLD=70    # Success percentage threshold (default: 70)
```

### Test 2: Region Failover

Tests geographic failover when a region becomes unhealthy.

**How it works:**
1. All traffic routes to primary region (East US)
2. Simulate region failure by disabling backend origin
3. Front Door health probes detect failure
4. Traffic automatically routes to secondary region (West US)

**Usage:**
```bash
cd tests

# Show help and available commands
./test-region-failover.sh help

# Verify all regions are healthy
./test-region-failover.sh baseline

# Check region routing consistency
./test-region-failover.sh consistency

# Show Front Door and origin health status
./test-region-failover.sh status

# Run all read-only tests
./test-region-failover.sh all

# ⚠️ Full failover simulation (modifies Front Door!)
./test-region-failover.sh failover
```

**Configuration Options:**
```bash
export REQUEST_COUNT=10        # Number of test requests (default: 10)
export SUCCESS_THRESHOLD=80    # Success percentage threshold (default: 80)
export HEALTH_PROBE_WAIT=60    # Seconds to wait for health probes (default: 60)
```

> **Warning**: The `failover` command will temporarily disable Front Door origins. Use with caution in production environments!

### Quick Test Example

```bash
# Set required environment variable
export APIM_SUBSCRIPTION_KEY="your-key-here"

# Run basic health checks
./tests/test-capacity-spillover.sh baseline
./tests/test-region-failover.sh baseline

# Full test suite
./tests/test-capacity-spillover.sh all
./tests/test-region-failover.sh all
```

## 💰 Cost Estimates

| Resource | SKU | Estimated Monthly Cost |
|----------|-----|------------------------|
| Azure Front Door | Premium | ~$35 + usage |
| API Management | Premium (2 units) | ~$5,600 |
| Azure OpenAI | Standard (PAYG) | Usage-based |

> **Note**: APIM Premium is required for multi-region deployment. For development/testing, consider using a single-region setup with Developer tier.

## 🔒 Security Considerations

- **Managed Identity**: APIM uses managed identity to access Azure OpenAI
- **No API Keys in Code**: All authentication handled via Azure RBAC
- **WAF Protection**: Front Door WAF policy in detection mode (switch to prevention for production)
- **Network Security**: Consider adding Private Endpoints for production deployments

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Azure Architecture Center](https://docs.microsoft.com/azure/architecture/)
- [Azure OpenAI Best Practices](https://learn.microsoft.com/azure/ai-services/openai/concepts/advanced-prompt-engineering)
- [APIM Backend Pool Documentation](https://learn.microsoft.com/azure/api-management/backends)
