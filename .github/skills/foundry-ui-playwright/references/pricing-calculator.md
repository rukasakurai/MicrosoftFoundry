# Azure Pricing Calculator navigation notes

Read this when using Playwright MCP to inspect the public Azure Pricing Calculator:
https://azure.microsoft.com/en-us/pricing/calculator/

Keep the session public/signed-out unless the user explicitly asks otherwise. This page
does not need Azure portal auth, and signing in can create avoidable account/tenant risk.

## High-value gotchas

- The calculator is not an IaC-aware estimator. It will not read this repo's Bicep or
  infer usage from `azd` parameters; use it to inspect product meters and assumptions.
- "Microsoft Foundry" cost is not one calculator item. Expect to assemble separate
  products/meters: Foundry model tokens, Azure AI Search / agentic retrieval, Azure
  Monitor / Log Analytics, and any tool-specific services.
- Product labels differ across surfaces. The Retail Prices API still exposes AI Search
  under `Azure Cognitive Search`, while model meters can appear under `Foundry Models`.
  Do not assume the calculator search label, portal label, and billing meter name match.
- A model deployment's Bicep capacity is not a monthly bill by itself for standard
  token-based deployments. The cost-driving inputs are workload assumptions such as
  input/output tokens, retrieval tokens, telemetry GB, and Search service hours.
- Treat calculator output as a dated estimate. Actual subscription cost should be
  checked separately in Cost Management when the question is "what did this workload
  actually cost?"

## Minimal navigation approach

1. Open the calculator page.
2. Search for one product/meter family at a time.
3. Add only the line items needed for the repo surface being analyzed.
4. Record the assumptions beside the estimate; do not present calculator defaults as
   repo-derived facts.
