# AGENTS.md

## Repository Purpose

This repository provides **Infrastructure-as-Code (IaC) for Microsoft Foundry**, using Bicep templates and Azure Developer CLI (azd).

**Current State:** The repository is actively used for provisioning Microsoft Foundry infrastructure on Azure.

## Collaboration & Decision-Making Style

- **Infrastructure-first**: Prioritize infrastructure stability and reproducibility
- **Start lean**: Prefer minimal, focused implementations over comprehensive solutions
- **Minimize changes**: Make the smallest possible modifications to achieve the goal
- **Defer specifics**: Avoid hardcoding environment-specific values (tenant IDs, subscription IDs, secrets)
- **Public-safe by default**: Never suggest or add sensitive information (secrets, Azure IDs, API keys)
- **Use azd patterns**: Follow Azure Developer CLI conventions for infrastructure and deployment
- **Bicep best practices**: Use parameterization, abbreviations, and modular design
- **Validate assumptions**: Test infrastructure changes in isolated environments before committing
- **Document limitations**: Clearly document known limitations and migration paths rather than hiding technical debt

## Constraints & Assumptions

### Infrastructure

- **Bicep as IaC language**: All infrastructure is defined using Bicep
- **azd integration**: Deployment is orchestrated through Azure Developer CLI
- **Resource naming**: Use abbreviations.json for consistent resource naming conventions
- **Environment-specific**: Support multiple environments (dev, staging, prod) through azd environments

### Security & Configuration

- **No secrets or identifiers**: All Azure/cloud credentials must be configured per deployment environment
- **OIDC for CI/CD**: Use OpenID Connect for GitHub Actions authentication (when configured)
- **Public network access**: Default to enabled for development; can be restricted per environment
- **Managed identities**: Use system-assigned managed identities for Azure resources

### Development & Deployment

- **Primary language**: .NET 10 is the preferred implementation language
- **No license file**: License choice is deferred to repository owner
- **Minimal CI/CD**: CI/CD patterns should be added as needed for the project
- **Region flexibility**: Support deployment to any Azure region with AI Services availability
- **SKU parameterization**: Allow customization of service tiers through parameters

## Agent Roles & Responsibilities

When working on this repository, AI agents should:

1. **For Infrastructure Changes:**
   - Review existing Bicep templates and follow established patterns
   - Validate parameter types, constraints, and default values
   - Ensure changes are compatible with azd deployment workflow
   - Test deployments in non-production environments

2. **For Documentation Updates:**
   - Keep deployment guides synchronized with infrastructure changes
   - Update configuration examples when parameters change
   - Maintain accuracy of resource descriptions and capabilities
   - Document known limitations and future migration paths transparently

## Technology Reference

> ⚠️ **Important:** Microsoft Foundry and Azure AI Foundry are **not interchangeable** and use **different ARM resource providers**. This section clarifies the technologies used in this repository.

The Microsoft AI ecosystem evolves rapidly, and terminology can be confusing. This reference documents the precise technical identifiers for technologies used in this repository.

| Technology Name | Technical Identifier | Status | Purpose | Distinct From | Synonyms/Aliases | Last Verified |
|-----------------|---------------------|--------|---------|---------------|------------------|---------------|
| **Microsoft Foundry** | `Microsoft.CognitiveServices/accounts` (kind: `AIServices`) | Preview | Multi-modal AI services platform using Cognitive Services ARM provider | Azure AI Foundry (uses different ARM provider) | Azure AI Services, Cognitive Services AIServices | 2025-12-24 |
| **Foundry Projects** | `Microsoft.CognitiveServices/accounts/projects` | Preview | Organize AI solutions within a Cognitive Services account | Azure AI Foundry projects (different provider hierarchy) | Cognitive Services Projects | 2025-12-24 |
| **Foundry Applications** | `Microsoft.CognitiveServices/accounts/projects/applications` | Preview | Stable endpoints for publishing agents externally | — | — | 2025-12-24 |
| **Agent Deployments** | `Microsoft.CognitiveServices/accounts/projects/applications/agentDeployments` | Preview | Hosting infrastructure for published agents | — | — | 2025-12-24 |
| **Azure Developer CLI** | `azd` (CLI tool) | GA | Infrastructure deployment orchestration | Azure CLI (`az`), Terraform | azd | 2025-12-24 |
| **Bicep** | `.bicep` files, ARM templates | GA | Infrastructure-as-Code language for Azure | Terraform, Pulumi, ARM JSON | Azure Bicep | 2025-12-24 |
| **Azure AI Foundry** | `Microsoft.MachineLearningServices/workspaces` | GA | ML platform for model training and deployment | Microsoft Foundry (this repo uses Cognitive Services) | Azure Machine Learning, AML | 2025-12-24 |

### Key Distinctions

- **Microsoft Foundry** (this repository): Uses `Microsoft.CognitiveServices` ARM resource provider with `AIServices` kind. Focused on AI agents and cognitive services.
- **Azure AI Foundry**: Uses `Microsoft.MachineLearningServices` ARM resource provider. Focused on machine learning workspaces, model training, and MLOps.
- These are **separate products** with different ARM providers, APIs, and deployment patterns despite similar branding.
