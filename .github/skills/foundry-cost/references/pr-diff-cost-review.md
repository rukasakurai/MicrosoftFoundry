# Reviewing PR cost impact

Use this runbook when asked whether a PR changes Microsoft Foundry related cost.
This is a marginal-cost review, not a full deployment estimate.

## Inputs to inspect

Compare base vs head for:

- `infra/main.bicep` and parameter files: resources, conditionals, SKUs, model
  deployments, capacity settings, observability, Foundry IQ/Search, role assignments,
  and connections.
- `azure.yaml`: hooks that create post-provision data-plane objects.
- `scripts/`: agents, tools, knowledge bases, MCP connections, Search indexes,
  telemetry, guardrails, hosted compute, memory, or gateway setup.
- `README.md` and `docs/`: documented optional flows that can create tenant-plane,
  portal-only, or data-plane cost drivers.
- Agent Skill changes that alter cost-review guidance, pricing sources, or runbooks.

## Cost-driver checks

Apply the cost-driver map in `../SKILL.md`, then call out changes to:

- model name/version/SKU/capacity and standard-vs-PTU/provisioned-capacity trade-offs;
- Azure AI Search / Foundry IQ enablement, SKU, agentic retrieval, indexes, and data;
- observability resources, telemetry volume, and retention;
- Build/runtime guardrails and Content Safety usage;
- Purview/DSPM enablement, licensing, and PAYG billing;
- Defender for Cloud plan assumptions;
- Entra agent identity/registry/OIDC/OAuth features that imply premium licensing or
  tenant-governance dependencies;
- Azure API Management, gateways, remote tools, hosted compute, memory, and external
  services.

## Freshness rule

For any numeric estimate, record region, currency, timestamp/date, pricing source,
and whether values came from Retail Prices API, Azure Pricing Calculator, or Cost
Management `ActualCost`.

## Output shape

Keep the review short:

- **Added cost drivers**
- **Removed cost drivers**
- **Changed cost drivers**
- **Missing assumptions before a dollar estimate is meaningful**
- **Recommended follow-up**, only when the PR adds a cost surface that cannot be
  evaluated from the diff

Use [workload-assumptions.md](workload-assumptions.md) when the diff changes
volume-sensitive cost surfaces.
