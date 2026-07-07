# Foundry "Policies" (Operate → Compliance): what it governs, and what it doesn't

> ⚠️ **Preview (as of 2026-07-07); facts will change — verify against the linked Learn
> pages, the live portal, and `az policy definition list` before relying on this.** The
> **Operate → Compliance** workspace shows a **"Preview"** badge, and every guardrail
> policy definition behind this tab is `[Preview]`, `Audit`-only (no `Deny`).
>
> **A "policy" here *audits*; it does not *enforce*.** The Create-policy wizard's own
> footer says: *"Setting a policy does not automatically enforce guardrails."* To
> actually block unsafe content, configure a content filter / prompt shield on the
> deployment in **Build → Guardrails** (backed by
> [Azure AI Content Safety](https://learn.microsoft.com/azure/ai-services/content-safety/overview),
> which is **GA**) — not this tab.

References:
[Manage compliance and security](https://learn.microsoft.com/azure/foundry/control-plane/how-to-manage-compliance-security),
[Create a guardrail policy](https://learn.microsoft.com/azure/foundry/control-plane/quickstart-create-guardrail-policy),
[Guardrails overview](https://learn.microsoft.com/azure/foundry/guardrails/guardrails-overview).

## What it is

A **Create policy** wizard that writes an **Azure Policy** assignment requiring a
*minimum* guardrail control — a **risk**, an **intervention point** (user input / output),
and an **action** (annotate-and-block or annotate-only) — for model deployments across a
subscription or resource group, then **reports** each deployment's compliance on the
**Policies** / **Assets** tabs. The content-filtering definitions expose only `Audit`
(and `Disabled`) — verified via `az policy definition list` — so a policy **flags**
non-compliant deployments; it never denies them or filters content.

## What it is not

Not the thing that blocks unsafe prompts or responses at inference — that is a
**guardrail** (content filter / prompt shield) on the deployment, configured in
**Build → Guardrails**. Azure Policy governs resource *configuration* (audit, or deny at
deploy time), never inference-time content: an "annotate and block" *requirement* only
records whether a deployment *has* such a guardrail; it does not apply one.

### The GA alternatives

Two GA controls do the real work — use these, not the preview Policies tab:

- **Block unsafe content →** configure a **content filter / Prompt Shields** on the
  deployment in **Build → Guardrails** (Azure AI Content Safety, GA). This enforces at
  inference: a harmful or jailbreak prompt is blocked outright.
- **Restrict which models can be deployed →** assign the GA Azure Policy
  **`Foundry model deployments should only use approved models`** (`Deny`). Caveat: it
  targets the **data-plane** type (`Microsoft.CognitiveServices.Data/accounts/deployments`),
  so it stops portal/data-plane deploys but **ARM/Bicep (control-plane) deploys bypass it**
  (verified: a non-approved model blocked in the portal still deployed via Bicep).
