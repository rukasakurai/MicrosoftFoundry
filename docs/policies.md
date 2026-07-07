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

The **Create policy** wizard is a front-end over
**[Azure Policy](https://learn.microsoft.com/azure/governance/policy/overview)**:
submitting it creates an Azure Policy **assignment** (creating or deleting one needs the
**Resource Policy Contributor** role; deleting the Foundry policy removes the underlying
Azure Policy assignment).

**Scope is subscription or resource group only.** The wizard's scope step offers just
**Subscription** and **Resource group** — you *cannot* target an individual Foundry
resource (the Cognitive Services account) or an agent. That is inherent to Azure Policy:
an assignment applies to a management group / subscription / resource group, never a
single resource or sub-resource.

It *resembles* Azure AI Content Safety because its inputs **are** content-filter settings —
a **risk** (the Content Safety categories: hate, sexual, violence, self-harm, jailbreak,
profanity, indirect prompt injection, spotlighting, protected material), an **intervention
point** (user input / output), and an **action** (annotate-and-block / annotate-only). But
it doesn't configure a filter — it assigns the built-in **initiative** *[Preview]:
Guardrail for Cognitive Services Deployments*
(`policySetDefinition 5207647b-3e83-4e28-b836-c382cb5e2a2e`), which bundles the `[Preview]
Cognitive Services Deployments should only use allowed prompt / completion content
filtering` (plus `allowed control` / `control mode`) definitions — every one effect
**`Audit` / `Disabled`** (verified via `az policy set-definition show`). So it **audits**
whether each deployment's content filter meets that minimum and reports compliance on the
**Policies** / **Assets** tabs; it never applies a filter or blocks a deployment.

Reference:
[Azure Policy built-in initiatives — Cognitive Services](https://learn.microsoft.com/azure/governance/policy/samples/built-in-initiatives#cognitive-services)
and the [Foundry Tools policy reference](https://learn.microsoft.com/azure/ai-services/policy-reference#foundry-tools).

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
