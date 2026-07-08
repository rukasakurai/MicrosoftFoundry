---
name: foundry-cost
description: Use when analyzing Microsoft Foundry cost impact for this repo.
---

## Focus

Help the agent map this repo's Bicep/azd surface to cost drivers, estimate cost
only where usage assumptions are explicit, and observe actual spend separately in
Azure Cost Management.

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
