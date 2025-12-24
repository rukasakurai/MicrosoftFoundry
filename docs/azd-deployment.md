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
- **Cognitive Services Project**: Project for organizing AI solutions
- **Cognitive Services Application** (optional): Application container for agent deployments
- **Agent Deployment** (optional): Agent deployment resource for operationalizing AI agents

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
3. Provision the Cognitive Services Project

## Configuration

### Default Parameters

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| `location` | `japaneast` | Azure region for deployment |
| `cognitiveServicesSku` | `S0` | SKU for Azure AI Services |
| `projectDisplayName` | `Microsoft Foundry Project` | Display name for the project |
| `enableAgentDeployments` | `false` | Enable application and agent deployment resources |

### Customizing Parameters

You can override default parameters during deployment:

```bash
azd up --parameter location=eastus
```

Or edit the `infra/main.parameters.json` file before deployment.

#### Enabling Agent Deployments

To enable the application and agent deployment resources:

```bash
azd up --parameter enableAgentDeployments=true
```

#### Using Hosted Deployment Type

For hosted deployments with custom scaling:

```bash
azd up --parameter enableAgentDeployments=true --parameter agentDeploymentType=Hosted --parameter agentDeploymentMinReplicas=2 --parameter agentDeploymentMaxReplicas=5
```

### Environment Variables

After deployment, the following outputs are available as environment variables:

- `AZURE_LOCATION`: Deployment region
- `AZURE_TENANT_ID`: Azure AD tenant ID
- `COGNITIVE_SERVICES_NAME`: AI Services account name
- `COGNITIVE_SERVICES_ENDPOINT`: AI Services endpoint URL
- `PROJECT_NAME`: Project name
- `APPLICATION_NAME`: Application name (when `enableAgentDeployments` is true)
- `AGENT_DEPLOYMENT_NAME`: Agent deployment name (when `enableAgentDeployments` is true)

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

## Agent Deployments

### Overview

Agent deployments (`Microsoft.CognitiveServices/accounts/projects/applications/agentDeployments`) provide infrastructure to **publish and host** AI agents you've already built. This resource type is part of the Azure AI Services hierarchy:

```
accounts
  └── projects
        └── applications          ← Provides stable endpoint, identity, and governance
              └── agentDeployments ← Running instance that routes traffic to an agent version
```

> **Important**: These resources do NOT create AI agents. They create the infrastructure to publish/host agents you've built in the Foundry portal or via SDK.

> **New Agents Developer Experience (December 2025):** Microsoft has introduced an updated developer experience with new API concepts. See the [Migration Guide](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/migrate?view=foundry) for details on transitioning to the new Conversations and Responses APIs. The infrastructure provisioned by this template supports both legacy and new patterns.

### Understanding the Workflow

| Step | Action | How |
|------|--------|-----|
| 1 | Provision infrastructure | `azd up` (this template) |
| 2 | Create an agent | Foundry portal → Agents → Create agent, or via SDK |
| 3 | Publish the agent | Foundry portal → Publish Agent, or via REST API |

When you publish an agent from the Foundry portal, it automatically creates an application and deployment. The `enableAgentDeployments` parameter in this template pre-provisions empty application/deployment resources that can be updated later.

### When to Use Agent Applications

Publishing an agent to an application enables:

- **External sharing**: Share with teammates or customers without granting project access
- **Stable endpoint**: Update agent versions without changing the endpoint URL
- **Distinct identity**: Separate RBAC rules and audit trail from the project
- **User data isolation**: Each user's interactions are isolated from others
- **Azure Policy integration**: Govern the application as an ARM resource

### Deployment Types

- **Managed**: Azure manages the deployment infrastructure automatically
- **Hosted**: You control scaling with `minReplicas` and `maxReplicas` parameters

### Limitations

- Agent deployments require the `enableAgentDeployments` parameter to be set to `true`
- The resource type is in preview (`2025-10-01-preview` API version)
- Bicep type validation may not be available for this resource type until it reaches general availability
- **Agent logic/behavior must be created separately** (via the [Foundry portal](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/quickstart?view=foundry), SDK, or [REST API](https://learn.microsoft.com/en-us/rest/api/azureai/agents)) - Bicep provisions the hosting infrastructure and can register agent resources, but does not define the agent's code or instructions. See the [Azure AI Foundry Agents documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/overview?view=foundry) for details. *(As of December 2025; this may change as the service evolves.)*

### Example Usage

1. **Basic deployment with agent deployments enabled:**
   ```bash
   azd up --parameter enableAgentDeployments=true
   ```

2. **Custom application and deployment names:**
   ```bash
   azd up --parameter enableAgentDeployments=true \
          --parameter applicationName=my-ai-app \
          --parameter agentDeploymentName=my-agent-deployment
   ```

## Additional Resources

- [Azure Developer CLI Documentation](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure AI Services Documentation](https://learn.microsoft.com/en-us/azure/ai-services/)
- [Microsoft.CognitiveServices/accounts Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts)
- [Microsoft.CognitiveServices/accounts/projects/applications Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/projects/applications)
- [Microsoft.CognitiveServices/accounts/projects/applications/agentDeployments Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/projects/applications/agentdeployments)
- [Agents Migration Guide](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/migrate?view=foundry) - Guide to the new agents developer experience
- [Azure AI Foundry Agent Service REST API](https://learn.microsoft.com/en-us/rest/api/aifoundry/aiagents/) - REST API reference

## Documentation Test History

### 2024-12-22
- Result: PASS with fixes
- Platform/Context: Microsoft Surface Laptop, Windows local environment
- OS: Microsoft Windows 11 Enterprise Build 26200
- Shell: PowerShell 7.5.4 (Core)
- Tester: Automated Documentation Tester (with human intervention)
- Notes:
  - Human intervention required for: `azd auth login` (browser-based authentication), `azd init` (environment setup - used existing `doctest` environment), confirmation before `azd up` (resource creation)
  - **Fix applied**: Added `allowProjectManagement: true` property to the Cognitive Services account in [infra/main.bicep](../infra/main.bicep). This property is required for projects to be created as child resources under AIServices kind accounts. Without this property, deployment fails with error: "Project can only be created under AIServices kind account with allowProjectManagement set to true."
  - All deployment steps completed successfully after fix
  - Environment variables verified: `AZURE_LOCATION`, `AZURE_TENANT_ID`, `COGNITIVE_SERVICES_NAME`, `COGNITIVE_SERVICES_ENDPOINT`, `PROJECT_NAME` all returned correct values
