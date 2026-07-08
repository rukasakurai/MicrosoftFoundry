---
name: foundry-cost
description: Use when analyzing Microsoft Foundry cost impact for this repo.
---

## Focus

Help the agent answer cost-impact questions about this repo's Microsoft Foundry
baseline: what can incur cost, what usage assumptions are missing, and what changed
in a PR.

## When to use

- Before someone runs `azd up` and wants cost context.
- When explaining the cost model implied by this repo's architecture.
- During PR review when a change adds, removes, or changes cost drivers.

## How to analyze

1. Read the relevant repo surface first: `infra/main.bicep`, `azure.yaml`, active
   azd params/env values, and any scripts/docs that create data-plane artifacts.
2. List only enabled or changed cost drivers. For PRs, compare base vs head.
3. Separate repo-known facts from workload assumptions. The repo can show resources,
   regions, SKUs, model names, capacity settings, and feature toggles; it cannot know
   token volume, runs, retrieval calls, telemetry GB, Search uptime, hosted-compute
   hours, memory usage, or license counts unless the user provides them.
4. Use fresh pricing when giving numbers, or clearly date the estimate. Do not bake
   in prices without a freshness note.
5. Use Cost Management `ActualCost` only for already-incurred spend. Do not present
   calculator output as actual spend.

## Cost-driver map

| Repo surface | Driver | Notes |
| --- | --- | --- |
| Cognitive Services account/project | Container for billed usage | Usually not the meaningful monthly estimate by itself; cost appears through deployed models and invoked services. |
| Model deployment params | Model token, PTU, or GPU-style capacity meters | `modelCapacity` is throughput/quota for standard token-based deployments, not a monthly bill by itself. |
| `enableObservability=true` | Azure Monitor / Log Analytics | Estimate from telemetry GB and retention. Application Insights data lands in the workspace. |
| `enableFoundryIq=true` | Azure AI Search + agentic retrieval | Default off. `searchServiceSku=basic` is the repo baseline minimum; higher SKUs are a cost decision. |
| Agents, tools, hosted compute, memory | Indirect model/tool/search/compute/license meters | Agents are data-plane artifacts; include the services they invoke, not just the connection object. |

## Output

Keep reports short and assumption-bound:

- **Cost drivers:** enabled/changed resources and meters.
- **Missing assumptions:** the workload inputs needed before dollar estimates are
  meaningful.
- **Estimate or actuals:** dated estimate with source, or Cost Management actuals
  with scope/time range.

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
