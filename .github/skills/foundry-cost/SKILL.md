---
name: foundry-cost
description: Use when analyzing Microsoft Foundry cost impact for this repo.
---

## Focus

Help the agent map this repo's Bicep/azd surface to cost drivers, estimate cost
only where usage assumptions are explicit, and observe actual spend separately in
Azure Cost Management.

## Procedure

1. Read `infra/main.bicep` and the active `azd` parameters/env values first.
2. Split the deployment into cost surfaces:
   - always on: Cognitive Services account/project and the model deployment;
   - default on: Log Analytics + Application Insights when `enableObservability=true`;
   - optional: Azure AI Search + Foundry IQ connection when `enableFoundryIq=true`;
   - post-provision/data-plane: agents, runs, tools, and knowledge-base objects.
3. Classify each surface as **fixed/resource-hours**, **usage-based**, or **no
   independent meter identified**. Do not assign a dollar value without the needed
   usage assumptions.
4. For estimates, fetch live prices or use the Azure Pricing Calculator and record
   the date, region, SKU, meter names, and usage assumptions beside the result.
5. For existing deployments, query Cost Management `ActualCost` instead of using an
   estimate as evidence of spend.

## Repo cost-driver map

| Repo surface | Driver | Notes |
| --- | --- | --- |
| `modelName` / `modelVersion` / `modelSkuName` | model tokens or PTU/GPU-style capacity, depending on SKU | For standard token-based deployments, `modelCapacity` is throughput/quota, not a monthly bill by itself. |
| `enableObservability=true` | Log Analytics ingestion/retention plus Application Insights telemetry | Estimate from expected telemetry GB and retention, not merely from resource existence. |
| `enableFoundryIq=true` | Azure AI Search service hours/SKU plus retrieval workload | `searchServiceSku=basic` is the default/minimum for this baseline's agentic retrieval path. |
| Agents, runs, MCP tools, knowledge bases | underlying model/tool/search usage | Agents and knowledge-base objects are data-plane artifacts; cost comes from the services they invoke. |

## Output shape

When reporting cost impact, use this shape:

- **Provisioned resources:** list only the surfaces enabled by the current params.
- **Known fixed drivers:** resource-hours/SKUs that cost money even before workload.
- **Usage assumptions needed:** tokens, runs, retrieval volume, telemetry GB, Search
  hours, retention, or "none provided".
- **Estimate:** dated, with source and assumptions; omit dollar totals when inputs
  are missing.
- **Actual spend:** only from Cost Management `ActualCost`, with scope and time range.

## Gotchas

- The Azure Pricing Calculator is not IaC-aware. It will not read this repo's
  Bicep or infer usage from `azd` parameters.
- "Microsoft Foundry" is not one billing line. Expect model token meters, Azure AI
  Search / agentic retrieval meters, Azure Monitor / Log Analytics meters, and
  tool-specific services.
- Product names differ across surfaces. Billing data can show model usage under
  `Foundry Models`; the Retail Prices API can still expose AI Search under
  `Azure Cognitive Search`.
- For standard token-based model deployments, Bicep `capacity` is not a monthly
  bill by itself. The cost-driving inputs are workload assumptions such as
  input/output tokens, retrieval tokens, telemetry GB, and Search service hours.
- Do not present calculator output as actual spend. Use Cost Management
  `ActualCost` when the question is what the subscription already incurred.

## Official pricing links

- [Azure OpenAI pricing](https://azure.microsoft.com/pricing/details/azure-openai/)
- [Azure AI Search pricing](https://azure.microsoft.com/pricing/details/search/)
- [Azure Monitor pricing](https://azure.microsoft.com/pricing/details/monitor/)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)

For Azure Pricing Calculator UI navigation, see
[pricing-calculator.md](../foundry-ui-playwright/references/pricing-calculator.md).
