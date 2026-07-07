# Foundry "Policies" (Operate → Compliance): what it governs, and what it doesn't

> ⚠️ **This is a preview feature; the facts below will likely change quickly.** Verify
> against the linked Microsoft Learn pages, the live portal, and `az policy definition
> list` before relying on anything here.

> **Preview (as of 2026-07-07).** The **Operate → Compliance** workspace carries a
> visible **"Preview"** badge (verified live in the portal), and the built-in Azure
> Policy definitions this tab creates are all `[Preview]` (verified via
> `az policy definition list`).
>
> **"Policy" here means *audit*, not *enforcement*.** The wizard's own footer states:
> *"Guardrail policies set minimum compliance requirements, while guardrails are
> technical controls that enforce those requirements. Setting a policy does not
> automatically enforce guardrails."* Creating a policy does **not** protect any
> deployment on its own.
>
> **Want to actually enforce safety today? Use guardrails, not this tab.** Configure a
> content filter / prompt shield on the deployment in **Build → Guardrails** (backed by
> [Azure AI Content Safety](https://learn.microsoft.com/azure/ai-services/content-safety/overview),
> whose Prompt Shields and content filtering are **GA**). This tab is only preferable
> when you specifically want org-wide, admin-defined *compliance reporting* over which
> deployments meet a minimum guardrail bar — and accept preview + audit-only.

The Microsoft Foundry portal exposes a **Policies** tab under **Operate → Compliance**
whose framing ("policies", "compliance", "enforce") is easy to misread as: *creating a
policy here makes unsafe content get blocked across my deployments.* It does not do
that. This note draws the boundary so you pick the right control for your goal.

Authoritative references:
[Manage compliance and security in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/control-plane/how-to-manage-compliance-security),
[Quickstart: create a guardrail policy](https://learn.microsoft.com/azure/foundry/control-plane/quickstart-create-guardrail-policy),
[Guardrails and controls overview](https://learn.microsoft.com/azure/foundry/guardrails/guardrails-overview).

## What it is

A wizard (**Create policy**) that creates an **Azure Policy** assignment requiring a
*minimum* guardrail control — a **risk** (e.g. content harm), an **intervention point**
(user input / output), and an **action** (annotate-and-block or annotate-only) — for
model deployments across a subscription or resource group, then **reports** each
deployment's compliance on the **Policies** / **Assets** tabs. The built-in
content-filtering definitions expose only the **`Audit`** (and `Disabled`) effect —
verified via `az policy definition list` — so the policy **flags** non-compliant
deployments; it does not deny them and does not filter content.

## What it is not

It is **not** the thing that blocks unsafe prompts or responses at inference. That is
done by a **guardrail** (content filter / prompt shield) attached to the deployment,
configured in **Build → Guardrails** (a separate portal surface). Azure Policy
governs resource **configuration** (audit, or deny at deploy time), never inference-time
content. A policy with an "annotate and block" *requirement* only records whether a
deployment *has* such a guardrail; it does not apply one.

### If you want a GA path

- **Enforce safety on a deployment (GA):** set the content filter / Prompt Shields on
  the deployment in **Build → Guardrails** (Azure AI Content Safety — Prompt Shields and
  content filtering are GA). No preview, no audit-lag.
- **Govern a fleet via Azure Policy (GA, but narrow):** the only **generally available**
  built-in policy for Foundry deployments is
  `Foundry model deployments should only use approved models` (supports **`Deny`**) — it
  governs *which models* may deploy, **not** content-safety guardrails. Every
  content-filtering guardrail definition is still `[Preview]`, `Audit`-only.
