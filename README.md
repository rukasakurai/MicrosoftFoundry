# Microsoft Foundry

Infrastructure-as-Code (IaC) for deploying and managing Microsoft Foundry resources on Azure.

> ⚠️ **Technology Clarification:** Microsoft Foundry and Azure AI Foundry are **not interchangeable**—they use different ARM resource providers (`Microsoft.CognitiveServices` vs `Microsoft.MachineLearningServices`). See the [Technology Reference](AGENTS.md#technology-reference) for details.

## What This Is

This repository provides **Infrastructure-as-Code** for Microsoft Foundry, which currently includes:
- Bicep templates for provisioning Azure AI Services (Cognitive Services)
- Foundry project configuration
- A default model deployment so the baseline is runnable out of the box
- Observability (Log Analytics + Application Insights) connected to the project so agent runs are traceable in the portal (optional, on by default via `enableObservability`)
- Optional Foundry Guide feedback loop and authenticated browser client
- Azure Developer CLI (azd) integration for streamlined deployment
- Human and AI collaboration guidance (AGENTS.md)

**Current Focus:** This repository is primarily focused on IaC for Microsoft Foundry infrastructure, but may evolve to encompass broader scope in the future, such as application code, automation, or additional Azure services.

## Getting Started

### Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed
- [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) installed
- An active Azure subscription with Contributor role or higher

## Recommended Setup Order

| Step | Document | Purpose |
|------|----------|---------|
| **1** | [azure-oidc-setup.md](docs/azure-oidc-setup.md) | Configure GitHub Actions OIDC for automated deployments |
| **2** | [azd-deployment.md](docs/azd-deployment.md) | Deploy infrastructure with `azd up` |
| **3** | [agent-creation.md](docs/agent-creation.md) | Create AI agents programmatically |
| **4** *(optional)* | [foundry-guide-feedback-loop.md](docs/foundry-guide-feedback-loop.md) | Demonstrate feedback-to-GitHub issue automation |
| **5** *(optional)* | [foundry-guide-web-app.md](docs/foundry-guide-web-app.md) | Deploy an authenticated desktop/mobile browser client |
| **6** *(optional)* | [entra-agent-identity.md](docs/entra-agent-identity.md) | Enable agents to authenticate as themselves |
| **7** *(optional)* | [entra-agent-registry.md](docs/entra-agent-registry.md) | Register agents for visibility in Entra admin center |
| **8** *(optional)* | [agent-mcp-oauth.md](docs/agent-mcp-oauth.md) | Connect an agent to an OAuth-authenticated remote MCP server |

> **Note:** Step 1 (OIDC) is optional if you only plan to deploy locally. It's recommended when using GitHub Actions for CI/CD.