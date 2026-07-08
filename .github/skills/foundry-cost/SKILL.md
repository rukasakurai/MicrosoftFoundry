---
name: foundry-cost
description: Use when analyzing Microsoft Foundry cost impact for this repo.
---

## Focus

Turn this repo's Bicep/azd declarations into a Foundry cost view:

- **pre-flight estimate** before `azd up`;
- **architecture cost model** for readers;
- **marginal cost delta** for PR review.

Do not duplicate a generic pricing calculator. Use the repo's IaC as the source of
truth for what gets provisioned, then add live pricing and explicit workload
assumptions where the IaC cannot know usage.

## Procedure

1. **Derive the bill of materials from IaC.** Read `infra/main.bicep`, `azure.yaml`,
   and the active azd params/env values. List resources and conditionals without
   requiring a deployed environment.
2. **Map each resource to meters.** Assemble the split Foundry cost model manually:
   model tokens/PTUs/GPU-style capacity, Azure AI Search/agentic retrieval, Azure
   Monitor/Log Analytics, hosted-agent/container compute if introduced, memory if
   introduced, and tool/IQ connection licensing where relevant.
3. **Separate provisioned cost from workload cost.** IaC can identify SKUs,
   regions, model names, and toggles; it cannot infer tokens, runs, retrieval
   volume, telemetry GB, or user/tool license counts.
4. **Fetch fresh pricing or date the estimate.** Prefer live pricing sources when
   possible; otherwise use the Azure Pricing Calculator and record the date, region,
   SKU, meter name, and assumptions. Never silently bake in stale prices.
5. **For PRs, compare base vs head.** Diff the IaC/azd surface and report only the
   marginal cost drivers added, removed, or changed.
6. **For real spend, use Cost Management.** Calculator output is not evidence of
   incurred cost; use `ActualCost` with scope and time range.

## Repo cost-driver map

| Repo surface | Driver | Notes |
| --- | --- | --- |
| Cognitive Services account/project | no standalone monthly estimate from IaC alone | The account/project is the container; cost usually appears through deployed models and invoked services. |
| `modelName` / `modelVersion` / `modelSkuName` | model tokens, PTUs, or GPU-style capacity depending on SKU/model family | Major trade-off: standard token billing vs reserved/provisioned capacity. For standard token-based deployments, `modelCapacity` is throughput/quota, not a monthly bill by itself. |
| `enableObservability=true` | Log Analytics ingestion/retention plus Application Insights telemetry | Default on. Estimate from expected telemetry GB and retention, not from resource existence alone. |
| `enableFoundryIq=true` | Azure AI Search service hours/SKU plus agentic retrieval workload | Default off. `searchServiceSku=basic` is the baseline minimum used here; higher SKUs are a cost decision. |
| Agents and MCP/tool use | underlying model, tool, search, hosted compute, memory, or license meters | Agents are data-plane artifacts. If a PR adds hosted agents, external tools, memory, or paid connections, add those meters even when Bicep only shows the connection. |

## Required output shape

When reporting cost impact, use this shape:

- **Bill of materials:** enabled resources, params, region, SKU/model/version, and
  whether each came from default IaC or an override.
- **Meter map:** the Azure product/meter family for each resource; call out hidden
  or indirect meters.
- **Assumptions required:** tokens, PTUs, runs, retrieval volume, telemetry GB,
  Search hours, hosted compute hours, memory, license/user counts, or "not provided".
- **Estimate:** dated, sourced, and assumption-bound. If assumptions are missing,
  say what cannot be priced instead of inventing a dollar amount.
- **PR delta:** for review, added/removed/changed cost drivers vs the base branch.
- **Actual spend:** only from Cost Management `ActualCost`, with scope and time range.

## Gotchas

- The Azure Pricing Calculator is not IaC-aware. It will not read this repo's
  Bicep or infer usage from `azd` parameters.
- "Microsoft Foundry" is not one billing line. Expect several calculator/products
  and billing meter families that must be assembled by hand.
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

- [Azure OpenAI pricing](https://azure.microsoft.com/pricing/details/azure-openai/)
- [Azure AI Search pricing](https://azure.microsoft.com/pricing/details/search/)
- [Azure Monitor pricing](https://azure.microsoft.com/pricing/details/monitor/)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)

For Azure Pricing Calculator UI navigation, see
[pricing-calculator.md](../foundry-ui-playwright/references/pricing-calculator.md).
