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
- **Model deployment**: Default model used by the agent creation examples
- **Observability**: Optional Log Analytics + Application Insights, enabled by default

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

### Customizing Parameters

You can override default parameters during deployment:

```bash
azd up --parameter location=eastus
```

Or edit the `infra/main.parameters.json` file before deployment.

### Environment Variables

After deployment, common outputs are available as environment variables:

- `AZURE_LOCATION`: Deployment region
- `AZURE_TENANT_ID`: Microsoft Entra tenant ID
- `COGNITIVE_SERVICES_NAME`: AI Services account name
- `COGNITIVE_SERVICES_ENDPOINT`: AI Services endpoint URL
- `MODEL_DEPLOYMENT_NAME`: Deployed model name
- `PROJECT_NAME`: Project name
- `PROJECT_ENDPOINT`: Foundry project data-plane endpoint
- `APPLICATION_INSIGHTS_NAME`: Application Insights component name when observability is enabled
- `LOG_ANALYTICS_WORKSPACE_NAME`: Log Analytics workspace name when observability is enabled
- `FOUNDRY_GUIDE_WEB_APP_NAME`: App Service app name when the browser client is enabled
- `FOUNDRY_GUIDE_WEB_APP_URL`: App Service URL when the browser client is enabled

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

## Creating Prompt Agents

This template provisions **infrastructure only** (account, project, model deployment). The repository's `prompt agent` examples are created separately after `azd up` through the project data-plane `/agents` API. New agents receive a stable endpoint when created; publishing refers to distributing that endpoint through Microsoft 365 or Teams. See [agent-creation.md](agent-creation.md) and [Agent Terminology](../AGENTS.md#agent-terminology).

Set `ENABLE_FOUNDRY_GUIDE=true` to opt into the [Foundry Guide feedback-loop sample](foundry-guide-feedback-loop.md). The post-provision hook creates or reuses the prompt agent after infrastructure deployment.

Set `ENABLE_FOUNDRY_GUIDE_WEB_APP=true` to add the opt-in
[authenticated browser client](foundry-guide-web-app.md). It provisions one Linux
Azure App Service web app, its plan and managed identity, and short-lived
feedback-correlation storage.

## Verifying Evaluation Visibility

With observability enabled, run one synthetic response through
[response-ID evaluation](https://learn.microsoft.com/azure/foundry/how-to/develop/cloud-evaluation#agent-response-evaluation):

```bash
azd env select <environment-name>
./scripts/evaluate-agent-response.sh --output /tmp/evaluation-result.json
```

Success produces a numeric `builtin.coherence` score and classifies the
correlated Application Insights event as `scored_automated_evaluation`. The
script also distinguishes evaluator errors, missing events, end-user feedback,
builder feedback, and connection or permission failures. Human-only results
identify the observed feedback sources.

The output file contains local correlation IDs for matching the response in
**Build → Agents → evaluation-visibility-agent → Traces**. Do not publish it or
evaluation reports, which can contain prompts, responses, evaluator reasoning,
and signed download URLs.

Response-ID evaluation and `builtin.coherence` are not marked Preview in
Microsoft Learn as of 2026-07-14. The Trace **Evaluation** column used for the
visual check is Preview as of that date.

## Additional Resources

- [Azure Developer CLI Documentation](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure AI Services Documentation](https://learn.microsoft.com/en-us/azure/ai-services/)
- [Microsoft.CognitiveServices/accounts Bicep Reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts)

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

### 2026-07-14
- Result: PASS with fixes
- Platform/Context: Linux, isolated azd environment, synthetic data only
- Tester: GitHub Copilot CLI with Playwright MCP
- Notes:
  - Clean provisioning completed in 132 seconds.
  - Response-ID evaluation produced a numeric `builtin.coherence` score and a correlated `scored_automated_evaluation` workspace event.
  - The matching Trace **Evaluation** cell displayed `coherence: 5`.
  - Clarified that response-ID evaluation and `builtin.coherence` are not marked Preview, while the Trace **Evaluation** column is Preview as of 2026-07-14.
