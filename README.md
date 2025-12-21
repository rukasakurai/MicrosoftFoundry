# Microsoft Foundry

Infrastructure-as-Code (IaC) for deploying and managing Microsoft Foundry resources on Azure.

## What This Is

This repository provides **Infrastructure-as-Code** for Microsoft Foundry, which currently includes:
- Bicep templates for provisioning Azure AI Services (Cognitive Services)
- Foundry project configuration
- Application and agent deployment resources for operationalizing AI agents
- Azure Developer CLI (azd) integration for streamlined deployment
- Human and AI collaboration guidance (AGENTS.md)

**Current Focus:** This repository is primarily focused on IaC for Microsoft Foundry infrastructure, but may evolve to encompass broader scope in the future, such as application code, automation, or additional Azure services.

## Getting Started

### Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed
- [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) installed
- An active Azure subscription with Contributor role or higher

### Quick Deployment

1. **Authenticate with Azure:**
   ```bash
   azd auth login
   ```

2. **Initialize the environment:**
   ```bash
   azd init
   ```

3. **Deploy the infrastructure:**
   ```bash
   azd up
   ```

4. **Enable agent deployments (optional):**
   ```bash
   azd up --parameter enableAgentDeployments=true
   ```

For detailed deployment instructions and configuration options, see [docs/azd-deployment.md](docs/azd-deployment.md).
