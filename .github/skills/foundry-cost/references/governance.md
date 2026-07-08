# Cost governance boundaries

Use this reference to decide where a cost control belongs. Microsoft Foundry cost is
not controlled only by Bicep; some controls live in runtime design, tenant governance,
or review process.

## Control map

| Layer | Controls that belong here | Examples / notes |
| --- | --- | --- |
| Repo IaC | Resources, SKUs, default feature toggles, retention, baseline connections | `infra/main.bicep`, `enableObservability`, `enableFoundryIq`, Search SKU, model deployment SKU/capacity |
| Runtime workload design | Workload volume, retries, tool loops, cache behavior, guardrails, rate limits | Token volume, agentic retrieval calls, hosted compute hours, Content Safety usage, memory use |
| Subscription governance | Budgets, Cost Management, Defender plans, Azure Policy, quotas | Actual spend and plan state can be outside this repo's resource group or Bicep |
| Tenant governance | Entra licensing, app registrations, admin consent, Purview/DSPM licensing/PAYG | Required for identity, DLP, compliance, and some agent governance flows |
| Review process | PR cost-delta checks, estimate freshness, explicit assumptions, follow-up issues | Use `pr-diff-cost-review.md`; record region/currency/date/source for numeric estimates |

## Practical rules

- If a cost is created by a declared Azure resource or parameter, prefer IaC defaults
  or parameterization.
- If a cost is driven by volume, require an explicit workload assumption instead of
  guessing.
- If a cost is tenant/subscription-plane, do not assume the resource-group estimate
  captures it.
- If a PR adds a new cost surface but not enough information to estimate it, report
  the missing assumption rather than blocking on a fake number.
- If a control is intentionally manual (for example a portal or tenant admin step),
  document the boundary instead of trying to hide it in Bicep.
