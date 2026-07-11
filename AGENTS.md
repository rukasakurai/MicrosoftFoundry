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
- **E2E testing before merge**: Changes must be validated end-to-end (from a clean `azd up` through the affected flow) before merging to `main`. How much testing — including whether to run wider regression — is a per-PR judgment call. The repository owner may override this requirement when necessary; the override should be visible (e.g., noted in the PR). Fully-automated CI E2E is a non-goal for now; a human-attested check with an easy owner override is preferred. For the runnable procedure and the map of testable surfaces, see the [`e2e-foundry-baseline`](.github/skills/e2e-foundry-baseline/SKILL.md) skill.
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
   - Avoid adding troubleshooting sections unless explicitly requested by the user

## Technology Reference

> ⚠️ **Important:** Microsoft Foundry and Azure AI Foundry are **not interchangeable** and use **different ARM resource providers**. This section clarifies the technologies used in this repository.

> ⚠️ **Documentation Confusion Warning:** Microsoft's official documentation states "Azure AI Foundry is now Microsoft Foundry" from a **branding perspective**. However, from an **Azure Resource Manager technical perspective**, these remain **distinct products** with different resource providers. During the documentation transition period, public documentation may use "Azure AI Foundry" and "Microsoft Foundry" interchangeably. **In this repository, we maintain strict technical distinctions** based on ARM resource providers, not branding.

The Microsoft AI ecosystem evolves rapidly, and terminology can be confusing. This reference documents the precise technical identifiers for technologies used in this repository.

| Technology Name | Technical Identifier |
|-----------------|---------------------|
| **Microsoft Foundry** | `Microsoft.CognitiveServices/accounts` (kind: `AIServices`) |
| **Foundry Projects** | `Microsoft.CognitiveServices/accounts/projects` |
| **Foundry Applications** | `Microsoft.CognitiveServices/accounts/projects/applications` |
| **Agent Deployments** | `Microsoft.CognitiveServices/accounts/projects/applications/agentDeployments` |
| **Azure AI Foundry (Hub)** | `Microsoft.MachineLearningServices/workspaces` (kind: `Hub`) |
| **Azure AI Foundry (Project)** | `Microsoft.MachineLearningServices/workspaces` (kind: `Project`) |
| **Azure Machine Learning** | `Microsoft.MachineLearningServices/workspaces` (kind: `Default`) |
| **Microsoft Agent SDK (.NET)** | NuGet: `Microsoft.Agents.AI.*` |
| **Foundry IQ (knowledge base / RAG)** | Azure AI Search agentic retrieval (`Microsoft.Search`), data-plane; reached from Foundry via a connection |

### Agent Terminology

Foundry uses similar labels across different product surfaces. They are not one hierarchy.

Writing and naming rules:

- Render exact classifications and feature names in backticks, such as `prompt agent`, `hosted agent`, `custom agent`, `external agent`, and `AI Red Teaming Agent`.
- Use product and service names without backticks, such as Microsoft Foundry, Foundry Agent Service, and Foundry Control Plane.
- Use bold for portal labels and navigation.
- Avoid the bare word *agent*; use the exact classification when relevant.
- Use *agentic application* only when planning, tool use, state, goal pursuit, or multistep autonomy warrants it.

Technical boundaries:

- Foundry Agent Service stores `prompt agent`, `hosted agent`, and `external agent` as project-scoped data-plane records. In that API, the record contains a `definition` object whose `kind` field identifies the classification.
- This data-plane `definition.kind` is not an ARM resource type or ARM `kind`.

Classifications:

- **`prompt agent` — Foundry Agent Service.** Defined through model, instructions, and tools; Agent Service runs the managed runtime. Its data-plane definition uses `"kind": "prompt"`.
- **`hosted agent` — Foundry Agent Service.** Application code is supplied as a container image or source archive; Agent Service manages its compute and endpoint. Its data-plane definition uses `"kind": "hosted"`.
- **Control Plane `custom agent` — Foundry Control Plane.** A separately hosted runtime exposes a reachable endpoint that is registered with Control Plane. Azure API Management proxies client requests to that endpoint. It has no Agent Service `definition.kind`; Control Plane inventory identifies its source as `FoundryCustom`.
- **Agent Service `external agent` — Foundry Agent Service, preview.** A separately hosted runtime is registered through metadata and an `otel_agent_id` for tracing and evaluation. Foundry does not host, proxy, or invoke it. Its data-plane definition uses `"kind": "external"`.
- **`AI Red Teaming Agent` — Foundry evaluation capability.** This Foundry-managed service generates adversarial test items and runs the evaluation workflow. It has no Agent Service `definition.kind`; its artifacts use project data-plane evaluation endpoints such as `/openai/evals`.
- **Application using Foundry APIs — not a Foundry classification.** Application code may call model inference or the Responses API without creating an Agent Service record. It therefore has no `definition.kind`.

These labels describe product integration and hosting. They do not by themselves establish agentic behavior.

References: [Agent Service `prompt agent` and `hosted agent`](https://learn.microsoft.com/azure/foundry/agents/overview), [Control Plane `custom agent`](https://learn.microsoft.com/azure/foundry/control-plane/register-custom-agent), [Agent Service `external agent`](https://learn.microsoft.com/azure/foundry/agents/how-to/register-external-agent), and [`AI Red Teaming Agent`](https://learn.microsoft.com/azure/foundry/concepts/ai-red-teaming-agent).

### Key Distinctions

- **Microsoft Foundry** (this repository): Uses `Microsoft.CognitiveServices` ARM resource provider with `AIServices` kind. Focused on AI agents and cognitive services.
- **Azure AI Foundry**: Uses `Microsoft.MachineLearningServices` ARM resource provider with Hub/Project architecture (kind: `Hub` or `Project`).
- **Azure Machine Learning**: Uses `Microsoft.MachineLearningServices` ARM resource provider with kind: `Default`. Traditional ML workspace for model training and MLOps.
- These are **separate products** with different ARM providers, resource kinds, APIs, and deployment patterns despite similar branding.
- **Foundry IQ / RAG**: Perceived as a Foundry feature (the portal **Knowledge** tab), but a knowledge base and its knowledge sources are **Azure AI Search data-plane objects** (`Microsoft.Search`), created via the AI Search REST API / SDK / portal — **not** ARM/Bicep and **not** the `CognitiveServices` provider. Foundry reaches them through a **connection**, the same architectural shape as connecting to Storage, Cosmos, or a third-party system. Agentic retrieval is GA in the AI Search `2026-04-01` REST API; the Foundry and Azure portal surfaces are preview. This repo treats Foundry IQ as the in-scope RAG path (not the plain `azure_ai_search` tool); how far it provisions the substrate (e.g. a Foundry→AI Search connection) is still open (#31).
