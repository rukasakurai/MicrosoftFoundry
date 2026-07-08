---
name: foundry-cost
description: Guidance for analyzing Microsoft Foundry related cost drivers, hidden billing surfaces, and pricing-source gotchas. Use when asked to estimate or explain costs, and estimate cost impact of changes.
---

## Cost-driver map

| Repo surface | Driver | Notes |
| --- | --- | --- |
| Cognitive Services account/project | Container for billed usage | Usually not the meaningful monthly estimate by itself; cost appears through deployed models and invoked services. |
| Model deployment params | Model token, PTU, or GPU-style capacity meters | `modelCapacity` is throughput/quota for standard token-based deployments, not a monthly bill by itself. |
| `enableObservability=true` | Azure Monitor / Log Analytics | Estimate from telemetry GB and retention. Application Insights data lands in the workspace. |
| `enableFoundryIq=true` | Azure AI Search + agentic retrieval | Default off. `searchServiceSku=basic` is the repo baseline minimum; higher SKUs are a cost decision. |
| Agents, tools, hosted compute, memory | Indirect model/tool/search/compute/license meters | Agents are data-plane artifacts; include the services they invoke, not just the connection object. |
| Guardrails / runtime safety | Azure AI Content Safety and Foundry model/tool meters | Operate → Compliance views can be read-only; Build/runtime guardrails can drive usage indirectly through model, tool, and content-safety paths. |
| Operate → Compliance → Data security and governance | Microsoft Purview / DSPM licensing and PAYG meters | Not provisioned by Bicep. Check tenant licensing, Purview enablement, and PAYG billing before assuming $0. |
| Operate → Compliance → Security posture | Microsoft Defender for Cloud plans | Defender is subscription/security-plane, not a normal repo resource. Check plan enablement before excluding it. |
| Entra agent identity, registry, OIDC, OAuth | Microsoft Entra licensing or app/governance dependencies | App registrations and RBAC are usually not usage meters, but premium Entra features or tenant licenses can matter. |
| API gateways / remote tools | Azure API Management or external service charges | Not in the baseline Bicep today; include if scripts/docs/PRs add gateway, MCP, or API front-door infrastructure. |

## Cannot infer from this repo alone

Tokens, PTU utilization, Search query volume, agentic retrieval calls, telemetry GB,
Purview/DSPM usage, Defender plan state, hosted compute hours, memory usage, and
license counts.

## Reference runbooks

- [current-state-estimate.md](references/current-state-estimate.md) — estimate the
  current repo baseline or an azd environment.
- [pr-diff-cost-review.md](references/pr-diff-cost-review.md) — review marginal cost
  impact in a PR.
- [risks.md](references/risks.md) — separate direct Azure meter spend from indirect
  agentic/remediation/business cost risks.
- [governance.md](references/governance.md) — map cost controls to IaC, runtime
  workload design, subscription/tenant governance, and review process.
- [retail-prices-api.md](references/retail-prices-api.md) — query live public prices
  without falling into billing-taxonomy traps.

## Gotchas

- The Azure Pricing Calculator is not IaC-aware. It will not read this repo's
  Bicep or infer usage from `azd` parameters.
- "Microsoft Foundry" is not one billing line. Expect several product/meter families.
- Product names differ across surfaces. Billing data can show model usage under
  `Foundry Models`; Retail Prices API labels can still say `Azure OpenAI` under
  `Foundry Models`, and expose AI Search under `Azure Cognitive Search`. See
  [retail-prices-api.md](references/retail-prices-api.md).
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
- [Azure AI Content Safety pricing](https://azure.microsoft.com/pricing/details/content-safety/)
- [Azure AI Search pricing](https://azure.microsoft.com/pricing/details/search/)
- [Azure Monitor pricing](https://azure.microsoft.com/pricing/details/monitor/)
- [Microsoft Defender for Cloud pricing](https://azure.microsoft.com/pricing/details/defender-for-cloud/)
- [Microsoft Purview pricing](https://azure.microsoft.com/pricing/details/purview/)
- [Microsoft Entra pricing](https://www.microsoft.com/security/business/microsoft-entra-pricing)
- [Azure API Management pricing](https://azure.microsoft.com/pricing/details/api-management/)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)

For Azure Pricing Calculator UI navigation, see
[pricing-calculator.md](../foundry-ui-playwright/references/pricing-calculator.md).
