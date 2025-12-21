# Microsoft Foundry

Infrastructure-as-Code (IaC) for deploying and managing Microsoft Foundry resources on Azure.

## What This Is

This repository provides **Infrastructure-as-Code** for Microsoft Foundry, which currently includes:
- Bicep templates for provisioning Azure AI Services (Cognitive Services)
- Azure AI Foundry project configuration
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

For detailed deployment instructions and configuration options, see [docs/azd-deployment.md](docs/azd-deployment.md).

## Repository Structure

```
├── infra/              # Bicep infrastructure templates
│   ├── main.bicep      # Main infrastructure definition
│   └── main.parameters.json  # Default parameters
├── docs/               # Documentation
│   ├── azd-deployment.md     # Deployment guide
│   └── azure-oidc-setup.md   # OIDC setup instructions
├── azure.yaml          # Azure Developer CLI configuration
└── AGENTS.md           # AI agent collaboration guidance
```

## Infrastructure Components

The deployment provisions:
- **Azure AI Services (Cognitive Services)**: Multi-service AI resource of kind `AIServices`
- **AI Foundry Project**: Project resource for organizing AI workloads

## Configuration

### Azure OIDC (Optional)

For GitHub Actions integration, set up federated credentials and add the following repository secrets:
- `AZURE_CLIENT_ID` (repository variable)
- `AZURE_TENANT_ID` (repository secret)
- `AZURE_SUBSCRIPTION_ID` (repository secret)

See [docs/azure-oidc-setup.md](docs/azure-oidc-setup.md) for detailed setup instructions.

## Future Expansion

While currently focused on infrastructure provisioning, this repository may expand to include:
- Application code and services utilizing Foundry infrastructure
- CI/CD pipelines for automated deployment
- Additional Azure services integration
- Monitoring and observability tooling
- Development and testing utilities

## Contributing

Contributions are welcome! When contributing, please:
- Follow the collaboration guidelines in [AGENTS.md](AGENTS.md)
- Make minimal, focused changes
- Ensure changes are public-safe (no secrets or sensitive data)
- Update documentation as needed

## Additional Resources

- [Azure AI Services Documentation](https://learn.microsoft.com/en-us/azure/ai-services/)
- [Azure Developer CLI Documentation](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/)
- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)