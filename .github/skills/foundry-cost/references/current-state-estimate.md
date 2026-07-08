# Estimating cost for the current repo baseline

Use this runbook when estimating cost for the current `azd` environment or the
default repo baseline. Keep the estimate assumption-bound; do not turn missing
workload inputs into fake precision.

## Inputs to read first

1. `infra/main.bicep` for provisioned resources, defaults, conditionals, SKUs, model
   names, capacity settings, and outputs.
2. `azure.yaml` for azd hooks that create post-provision data-plane artifacts.
3. `.azure/<env>/config.json` and `.azure/<env>/.env` for environment overrides.
   Redact subscription, tenant, resource names, endpoints, and secrets in any report.
4. Relevant docs/scripts for optional data-plane or tenant-plane flows, especially
   `README.md`, `docs/operate/`, and agent/tool setup docs.

## Baseline checks

1. Resolve the active values:
   - environment name and Azure region;
   - model deployment name/model/version/SKU/capacity;
   - `enableObservability`;
   - `enableFoundryIq` and Search SKU;
   - any explicitly configured names that imply existing resources.
2. Apply the cost-driver map in `../SKILL.md`.
3. Do explicit negative checks for non-Bicep surfaces:
   - Purview/DSPM: enabled? licensed? PAYG billing linked?
   - Defender for Cloud: relevant plans enabled at subscription/resource scope?
   - Entra: any premium agent identity, governance, or tenant licensing dependency?
   - API Management/gateways: any APIM or external gateway introduced by scripts/docs?
   - Content Safety/guardrails: any runtime content-safety resource or usage?
4. Separate **idle/provisioned** costs from **workload** costs. The repo can usually
   identify resources and SKUs; it cannot infer tokens, runs, retrieval calls,
   telemetry GB, Search service hours or serverless compute/storage, hosted-compute
   hours, memory usage, or license counts.

## Pricing and actuals

- Use live pricing sources where practical, or date the estimate and list sources.
- The Retail Prices API can expose Foundry model meters under service/product names
  that differ from portal labels; verify meter names before using them.
- Use Cost Management `ActualCost` only when the user asks for incurred spend.
  Calculator or Retail Prices output is an estimate, not actual spend.

## Output shape

Keep reports short and assumption-bound:

- **Cost drivers:** enabled/changed resources and meters, including explicit
  negative checks.
- **Missing assumptions:** the workload inputs needed before dollar estimates are
  meaningful.
- **Estimate or actuals:** dated estimate with source, or Cost Management actuals
  with scope/time range.
