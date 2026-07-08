---
name: foundry-cost
description: Use when analyzing Microsoft Foundry cost impact for this repo.
---

## Focus

Use this skill for issue #55's problem: the repo shows **what** Microsoft Foundry
resources it provisions, but not **what they cost** or where the cost traps are.

Keep the problem broad. The answer might be a skill, doc, script, review checklist,
or some combination. Do not treat "an IaC-derived workflow" as the issue; that is
only one possible implementation.

The cost blind spot matters in three repo uses:

- **Deploying:** `azd up` has cost-relevant knobs but no pre-flight cost context.
- **Reading:** the repo teaches Foundry architecture without the cost model a reader
  would adopt, including hidden/non-obvious meters.
- **Extending:** PRs can add cost drivers without a clear way to discuss marginal
  cost impact.

## Procedure

1. Identify which use is in scope: deployer estimate, reader cost explanation, or
   contributor/PR cost delta.
2. Read the repo surface that drives cost: `infra/main.bicep`, `azure.yaml`, active
   azd params/env values, and relevant scripts/docs for data-plane features.
3. Explain the cost model implied by that surface. Foundry pricing is fragmented:
   model tokens, PTUs, GPU-hours, hosted-agent container compute, separately billed
   memory, Azure AI Search / agentic retrieval, Azure Monitor / Log Analytics, and
   tool/IQ connection licenses can all matter depending on the feature.
4. Separate what the repo can know from what it cannot know. IaC can reveal resources,
   SKUs, regions, model choices, and toggles; it cannot infer workload volumes such
   as tokens, runs, retrieval calls, telemetry GB, Search hours, or license counts.
5. If giving numbers, use fresh pricing or date the estimate. Do not silently bake
   in prices that will go stale.
6. If reviewing a PR, compare base vs head and name the added/removed/changed cost
   risks. Do not require a specific implementation unless the issue/PR does.

## Repo cost-driver map

| Repo surface | Driver | Notes |
| --- | --- | --- |
| Cognitive Services account/project | no standalone monthly estimate from IaC alone | The account/project is the container; cost usually appears through deployed models and invoked services. |
| `modelName` / `modelVersion` / `modelSkuName` | model tokens, PTUs, or GPU-style capacity depending on SKU/model family | Major trade-off: standard token billing vs reserved/provisioned capacity. For standard token-based deployments, `modelCapacity` is throughput/quota, not a monthly bill by itself. |
| `enableObservability=true` | Log Analytics ingestion/retention plus Application Insights telemetry | Default on. Estimate from expected telemetry GB and retention, not from resource existence alone. |
| `enableFoundryIq=true` | Azure AI Search service hours/SKU plus agentic retrieval workload | Default off. `searchServiceSku=basic` is the baseline minimum used here; higher SKUs are a cost decision. |
| Agents, tools, memory, hosted compute | underlying model/tool/search/compute/license meters | Agents are data-plane artifacts. If a PR adds hosted agents, external tools, memory, or paid connections, include those meters even when Bicep only shows a connection. |

## Output shape

Use the smallest shape that answers the scenario:

- **Deployer:** enabled resources, cost-driving params, required usage assumptions,
  and a dated estimate if assumptions are available.
- **Reader:** the cost model implied by the architecture, especially hidden meters
  and standard-vs-PTU/provisioned-capacity trade-offs.
- **Contributor/reviewer:** marginal cost drivers introduced or removed by the diff,
  plus any assumptions needed before a dollar estimate is meaningful.
- **Actual spend:** Cost Management `ActualCost` only, with scope and time range.

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
