---
name: foundry-cost
description: Use when analyzing Microsoft Foundry cost impact for this repo.
---

## Cost-driver map

| Repo surface | Driver | Notes |
| --- | --- | --- |
| Cognitive Services account/project | Container for billed usage | Usually not the meaningful monthly estimate by itself; cost appears through deployed models and invoked services. |
| Model deployment params | Model token, PTU, or GPU-style capacity meters | `modelCapacity` is throughput/quota for standard token-based deployments, not a monthly bill by itself. |
| `enableObservability=true` | Azure Monitor / Log Analytics | Estimate from telemetry GB and retention. Application Insights data lands in the workspace. |
| `enableFoundryIq=true` | Azure AI Search + agentic retrieval | Default off. `searchServiceSku=basic` is the repo baseline minimum; higher SKUs are a cost decision. |
| Agents, tools, hosted compute, memory | Indirect model/tool/search/compute/license meters | Agents are data-plane artifacts; include the services they invoke, not just the connection object. |
| Guardrails / runtime safety | Azure AI Content Safety and Foundry model/tool meters | Compliance views can be read-only, but runtime guardrails/content safety can still create usage meters. |
| Operate → Compliance → Data security and governance | Microsoft Purview / DSPM licensing and PAYG meters | Not provisioned by Bicep. Check tenant licensing, Purview enablement, and PAYG billing before assuming $0. |
| Operate → Compliance → Security posture | Microsoft Defender for Cloud plans | Defender is subscription/security-plane, not a normal repo resource. Check plan enablement before excluding it. |
| Entra agent identity, registry, OIDC, OAuth | Microsoft Entra licensing or app/governance dependencies | App registrations and RBAC are usually not usage meters, but premium Entra features or tenant licenses can matter. |
| API gateways / remote tools | Azure API Management or external service charges | Not in the baseline Bicep today; include if scripts/docs/PRs add gateway, MCP, or API front-door infrastructure. |

## Gotchas

- The Azure Pricing Calculator is not IaC-aware. It will not read this repo's
  Bicep or infer usage from `azd` parameters.
- "Microsoft Foundry" is not one billing line. Expect several product/meter families.
- Product names differ across surfaces. Billing data can show model usage under
  `Foundry Models`; the Retail Prices API can still expose AI Search under
  `Azure Cognitive Search`.
- For standard token-based model deployments, Bicep `capacity` is not a monthly
  bill by itself. The cost-driving inputs are workload assumptions such as
  input/output tokens, retrieval tokens, telemetry GB, and Search service hours.
- Non-obvious meters matter: PTUs, GPU-hours, hosted-agent container compute,
  separately billed memory, and tool/IQ connection licenses should be checked when
  those features appear in IaC, docs, scripts, or PR diffs.
- Do not present calculator output as actual spend. Use Cost Management
  `ActualCost` when the question is what the subscription already incurred.

## Official pricing links

- [Microsoft Foundry pricing](https://azure.microsoft.com/pricing/details/microsoft-foundry/)
- [Azure AI Search pricing](https://azure.microsoft.com/pricing/details/search/)
- [Azure Monitor pricing](https://azure.microsoft.com/pricing/details/monitor/)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)

For Azure Pricing Calculator UI navigation, see
[pricing-calculator.md](../foundry-ui-playwright/references/pricing-calculator.md).
