# Foundry "Guardrails" (Operate → Compliance): what it reviews, and what it doesn't

> ⚠️ **Preview (as of 2026-07-07); facts will change — verify against the linked Learn
> pages and the live portal before relying on this.** The **Operate → Compliance**
> workspace shows a **"Preview"** badge. Its **Guardrails** tab was verified live as a
> read-only coverage view, not a configuration surface.
>
> **A "Guardrails" tab here *reviews*; it does not *configure*.** To create, manage,
> or apply guardrails, use **Build → Guardrails**. The Compliance tab only helps spot
> coverage gaps across deployments.

References:
[Manage compliance and security](https://learn.microsoft.com/azure/foundry/control-plane/how-to-manage-compliance-security),
[Guardrails overview](https://learn.microsoft.com/azure/foundry/guardrails/guardrails-overview).

The Microsoft Foundry portal exposes **two different "Guardrails" surfaces**. The
Compliance one is easy to over-trust because it uses the same label as the Build
authoring surface. This note draws that boundary.

## What it is

The **Operate → Compliance → Guardrails** tab is a preview, read-only comparison view
for existing model deployments. In the live portal it showed:

- rows for model deployments;
- columns for guardrail coverage, including **Content harms**, **Jailbreak**,
  **Indirect prompt injections**, **Spotlighting**, **Profanity (Blocklist)**,
  **Protected materials code**, and **Protected materials text**;
- status values such as **On**, **Off**, **On (prompt only)**, and
  **On (completion only)**.

The only remediation path observed was indirect: deployment names linked back to
**Build → Guardrails**.

## What it is not

It is **not** where you create, edit, or apply guardrails. The live page had filters and
search, but no create/edit/toggle control. Use **Build → Guardrails** for the runtime
guardrail configuration.

It is also **not** the same thing as **Operate → Compliance → Policies**. The Policies
tab is the Azure Policy-backed configuration-governance surface; this Guardrails tab is
only a coverage review lens.
