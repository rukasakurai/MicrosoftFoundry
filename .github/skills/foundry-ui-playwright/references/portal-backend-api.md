# How the "New Foundry" portal talks to the backend

Read this when you need to inspect *what* a Foundry portal pane actually loads (e.g. to confirm a feature is real, debug an empty pane, or understand the "available through the Foundry portal only" wording in the docs). For normal navigation you don't need this — the nav map in `SKILL.md` is enough.

> [!IMPORTANT]
> **Foundry's Control Plane is in preview and this file documents preview-era internals.** Concrete identifiers below (resolver names, user-agent, the `/nextgen` path) are **high-churn** and several claims are expected to be invalidated as the product reaches GA. **Treat anything tagged 🔴/🟡 as possibly stale — re-verify before relying on it.** See "Re-verification" at the bottom.

## Confirmation log

| Field | Value |
| --- | --- |
| Last confirmed | **2026-06-15** |
| Confirmed by | Playwright MCP (`browser_network_requests` + `browser_network_request`) against the live portal |
| Env used | a Microsoft Foundry resource (`Microsoft.CognitiveServices/accounts`, kind `AIServices`) provisioned by this repo |
| Pane observed | Operate → Compliance |
| Control Plane status at confirmation | **Preview** (Overview/Assets/Compliance badged *Preview*; Quota/Admin not) |

When you re-verify, **update the row above** (date + what you checked) and adjust the volatility tags if reality has moved.

## Volatility legend

- 🟢 **Stable** — architectural, unlikely to change before/after GA.
- 🟡 **Medium** — preview-era naming; may be rebranded at GA.
- 🔴 **High** — internal implementation detail; can change at any time, no notice.

## The portal uses a private BFF, not public ARM

🟢 **(stable pattern)** The "New Foundry" experience is **not** driven by the public Azure Resource Manager API (`management.azure.com`). It calls a **private, portal-internal BFF** (backend-for-frontend). This *architecture* (portal → private BFF → fan-out to GA services) is expected to persist even as names change.

🟡 **(path may change)** Observed BFF request shape:

```
POST https://ai.azure.com/nextgen/api/query?<name>Resolver
POST https://ai.azure.com/nextgen/api/<name>
```

The `/nextgen/` segment is preview-era naming and may disappear once the new experience becomes the default.

🔴 **(names will likely change)** Example resolver names captured on **Operate → Compliance** — do **not** hardcode these; they are illustrative of the *pattern*, not a stable contract:

- `getCognitiveServicesAccountResolver`
- `listAzurePolicyComponentStatesResolver`
- `listAzurePolicyAssignmentsForSetDefinitionResolver`
- `getAiGateways`
- `listAllSubscriptionDeployments`

Distinguishing traits of these resolver calls (as of the confirmation date):

- 🟡 **No `api-version` query parameter** (the public ARM REST contract always requires one). *If this changes — i.e. these calls gain `api-version` or move to `management.azure.com` — it is a strong signal the layer is heading to a public/GA API.*
- 🔴 Request header `user-agent: AzureMachineLearningWorkspacePortal/AIFoundry` (legacy "MachineLearning" naming; likely to be rebranded).
- 🟢 Host is `ai.azure.com`, **not** `management.azure.com`.

## Implications when verifying docs

🟡 **(the claim most likely to flip at GA)** As of the confirmation date this is **not a supported/public API** — there is no documented, versioned REST/SDK surface for the Operate (Control Plane) *aggregation* layer. **This is the single claim most likely to be invalidated as Foundry reaches GA**; a documented Control Plane REST API appearing would supersede this file.

🟢 When a doc says a Control Plane feature is "available through the Foundry portal only", read it as: the portal is the only supported entry point; behind it, these private resolvers fan out to GA services (Azure Policy, Microsoft Defender for Cloud, Microsoft Purview, Cognitive Services). For automation, drive those GA services directly rather than the resolver endpoints.

## Re-verification

Run this to re-confirm and refresh the **Confirmation log** above. The steps are stable even though the values they return are not.

1. Sign in and open an Operate pane (see `SKILL.md` for auth + deep-link steps).
2. List the BFF calls (not ARM):
   ```
   browser_network_requests(filter="nextgen/api", static=false)
   ```
3. Inspect one call's headers to confirm the user-agent and the absence of `api-version`:
   ```
   browser_network_request(index=<n>, part="request-headers")
   ```
4. **Cross-check against GA signals** (any of these means this file likely needs a rewrite, not just a date bump):
   - The Operate panes lose their **Preview** badge in the portal.
   - A learn.microsoft.com page documents a **Control Plane / Operate REST API** with an `api-version` (search the Foundry REST reference under `learn.microsoft.com/rest/api/`).
   - The captured calls start carrying `api-version` or originate from `management.azure.com`.
5. Update the **Confirmation log** date + notes, retag any claims whose volatility changed, and remove/replace identifiers that no longer match.
