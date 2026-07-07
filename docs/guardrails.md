# Foundry "Guardrails": Build configures them; Operate reviews them

> ⚠️ **Verify against the live portal before relying on this.** Microsoft Foundry's
> guardrails UI is changing quickly, and some controls are preview. This note was
> verified live in the portal on **2026-07-07**.
>
> **There are two "Guardrails" surfaces.** **Build → Guardrails** is where you create,
> configure, and apply guardrails. **Operate → Compliance → Guardrails** is a
> read-only coverage matrix for comparing deployed guardrail settings across models.

References:
[Guardrails and controls overview](https://learn.microsoft.com/azure/foundry/guardrails/guardrails-overview),
[Manage compliance and security](https://learn.microsoft.com/azure/foundry/control-plane/how-to-manage-compliance-security),
[Intervention points and controls](https://learn.microsoft.com/azure/foundry/guardrails/intervention-points),
[Content filtering](https://learn.microsoft.com/azure/foundry-classic/foundry-models/concepts/content-filter).

## What it is

A **guardrail** is a named collection of controls applied to selected **models** or
**agents**. The Build page describes it this way: "Create, manage and apply them across
models or agents." In the live portal, **Build → Guardrails** has:

- a **Create** button;
- tabs for **Guardrails**, **Blocklists**, and **Integrations (Preview)**;
- guardrail rows showing name, type, and what each guardrail is applied to;
- a create flow for selecting controls, then assigning the guardrail to agents and
  model deployments.

The default controls visible in the create flow include **Jailbreak**, **Content harms**
(hate, sexual, self-harm, violence), and **Protected materials**. Other controls such as
**Indirect prompt injections**, **Spotlighting**, **PII**, and **Task adherence** appear
as optional or preview controls depending on the intervention point.

## The Compliance view

**Operate → Compliance → Guardrails** is different. It is part of the **Preview**
Compliance workspace and shows a matrix:

- rows: model deployments;
- columns: guardrail/control coverage such as **Content harms**, **Jailbreak**,
  **Indirect prompt injections**, **Spotlighting**, **Profanity (Blocklist)**,
  **Protected materials code**, and **Protected materials text**;
- cells: status values such as **On**, **Off**, **On (prompt only)**, and
  **On (completion only)**.

In the live portal, this page had subscription/project/date filters and search, but no
create/edit/toggle control. Clicking a deployment name linked back to
**Build → Guardrails**. That matches the Learn page's narrower description: this tab is
for comparing configurations and spotting coverage gaps.

## What it is not

**Operate → Compliance → Guardrails** is **not** where you configure protection. If a
deployment is missing a control, switch to **Build → Guardrails** to change the
guardrail, or use **Operate → Compliance → Policies** if your goal is Azure
Policy-backed configuration governance.

Be careful with Learn's broader "enforce" wording around the Compliance workspace. The
Guardrails tab itself is only a review lens. The neighboring **Policies** tab is the
Azure Policy surface, and in this repo's live checks its guardrail policies were
configuration-audit oriented; see [Foundry "Policies"](policies.md).
