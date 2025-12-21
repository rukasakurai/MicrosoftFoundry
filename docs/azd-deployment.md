# Azure Developer CLI (azd) Deployment Guide

This guide explains how to deploy Microsoft Foundry infrastructure using Azure Developer CLI (azd).

## Overview

This repository includes Bicep infrastructure-as-code (IaC) files to provision Azure AI Services resources compatible with Microsoft Foundry. The infrastructure is designed to work with Azure Developer CLI (azd) for streamlined deployment.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed
- [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) installed
- An active Azure subscription with appropriate permissions
- Contributor role (or higher) on the target subscription

## Infrastructure Components

The deployment provisions:

- **Resource Group**: Container for all resources
- **Azure AI Services (Cognitive Services)**: Multi-service resource of kind `AIServices`

## Quick Start

### 1. Authenticate with Azure

```bash
azd auth login
```

### 2. Initialize the environment

```bash
azd init
```

When prompted:
- Enter an environment name (e.g., `dev`, `staging`, `prod`)
- Select your Azure subscription
- Select the Azure location (default: `japaneast`)

### 3. Deploy the infrastructure

```bash
azd up
```

This command will:
1. Create a resource group
2. Provision the Azure AI Services account

## Configuration

### Default Parameters

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| `location` | `japaneast` | Azure region for deployment |
| `cognitiveServicesSku` | `S0` | SKU for Azure AI Services |

### Customizing Parameters

You can override default parameters during deployment:

```bash
azd up --parameter location=eastus
```

Or edit the `infra/main.parameters.json` file before deployment.

### Environment Variables

After deployment, the following outputs are available as environment variables:

- `AZURE_LOCATION`: Deployment region
- `AZURE_TENANT_ID`: Azure AD tenant ID
- `COGNITIVE_SERVICES_NAME`: AI Services account name
- `COGNITIVE_SERVICES_ENDPOINT`: AI Services endpoint URL

Access these values with:

```bash
azd env get-values
```

## Common Commands

```bash
# View current environment
azd env list

# Switch environments
azd env select <environment-name>

# Update infrastructure
azd provision

# View deployment outputs
azd env get-values

# Clean up resources
azd down
```

## Additional Resources

- [Azure Developer CLI Documentation](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure AI Services Documentation](https://learn.microsoft.com/en-us/azure/ai-services/)
- [Microsoft.CognitiveServices/accounts Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts)
