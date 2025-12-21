# AGENTS.md

## Repository Purpose

This repository provides **Infrastructure-as-Code (IaC) for Microsoft Foundry**, focusing on deploying and managing Azure AI Services and AI Foundry projects using Bicep templates and Azure Developer CLI (azd).

**Current State:** The repository is actively used for provisioning Microsoft Foundry infrastructure on Azure, including Cognitive Services accounts and AI Foundry projects.

**Future Evolution:** While currently focused on IaC, this repository may expand to include:
- Application code that utilizes the provisioned infrastructure
- CI/CD pipelines and automation workflows
- Additional Azure services and integrations
- Monitoring, logging, and observability components
- Development tools and utilities

## Collaboration & Decision-Making Style

- **Infrastructure-first**: Prioritize infrastructure stability and reproducibility
- **Start lean**: Prefer minimal, focused implementations over comprehensive solutions
- **Minimize changes**: Make the smallest possible modifications to achieve the goal
- **Defer specifics**: Avoid hardcoding environment-specific values (tenant IDs, subscription IDs, secrets)
- **Public-safe by default**: Never suggest or add sensitive information (secrets, Azure IDs, API keys)
- **Use azd patterns**: Follow Azure Developer CLI conventions for infrastructure and deployment
- **Bicep best practices**: Use parameterization, abbreviations, and modular design
- **Validate assumptions**: Test infrastructure changes in isolated environments before committing

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

3. **For Future Expansion:**
   - Consider how additions integrate with existing IaC
   - Maintain separation between infrastructure and application concerns
   - Document new components and their relationships
   - Follow established patterns for naming, tagging, and organization
