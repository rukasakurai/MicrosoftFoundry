# Foundry "Policies" (Operate → Compliance): what it governs, and what it doesn't

> ⚠️ **Preview (as of 2026-07-07); facts will change — verify against the linked Learn
> pages, the live portal, and `az policy definition list` before relying on this.** The
> **Operate → Compliance** workspace shows a **"Preview"** badge, and every guardrail
> policy definition behind this tab is `[Preview]`, `Audit`-only (no `Deny`).
>
> **A "policy" here *audits*; it does not *enforce*.** The Foundry portal's **Create
> policy** page says:
> *"Setting a policy does not automatically enforce guardrails."* To
> actually block unsafe prompts or outputs, configure a guardrail/content filter on the
> deployment in **Build → Guardrails** (backed by
> [Azure AI Content Safety](https://learn.microsoft.com/azure/ai-services/content-safety/overview),
> which is **GA**) — not this tab.

References:
[Manage compliance and security](https://learn.microsoft.com/azure/foundry/control-plane/how-to-manage-compliance-security),
[Create a guardrail policy](https://learn.microsoft.com/azure/foundry/control-plane/quickstart-create-guardrail-policy),
[Guardrails overview](https://learn.microsoft.com/azure/foundry/guardrails/guardrails-overview).

## What it is

The Foundry portal's **Create policy** page is a front-end over
**[Azure Policy](https://learn.microsoft.com/azure/governance/policy/overview)**:
submitting it creates an Azure Policy **assignment** (creating or deleting one needs the
**Resource Policy Contributor** role; deleting the Foundry policy removes the underlying
Azure Policy assignment).

**Scope is subscription or resource group only.** The scope step offers just
**Subscription** and **Resource group** — you *cannot* target an individual Foundry
resource (the Cognitive Services account) or an agent. That is inherent to Azure Policy:
an assignment applies to a management group / subscription / resource group, never a
single resource or sub-resource.

It *resembles* Azure AI Content Safety because its inputs describe required content-filter
configuration —
a **risk** (the Content Safety categories: hate, sexual, violence, self-harm, jailbreak,
profanity, indirect prompt injection, spotlighting, protected material), an **intervention
point** (user input / output), and an **action** (annotate-and-block / annotate-only). But
it doesn't configure a filter — it assigns the built-in **initiative** *[Preview]:
Guardrail for Cognitive Services Deployments*
(`policySetDefinition 5207647b-3e83-4e28-b836-c382cb5e2a2e`), which bundles the `[Preview]
Cognitive Services Deployments should only use allowed prompt / completion content
filtering` (plus `allowed control` / `control mode`) definitions — every one effect
**`Audit` / `Disabled`** (verified via `az policy set-definition show`). So it **audits
configuration compliance** — whether each deployment's content filter is configured to
meet that minimum — and reports that status on the **Policies** / **Assets** tabs; it
doesn't inspect runtime prompts/responses, apply a filter, or block a deployment.

Reference:
[Azure Policy built-in initiatives — Cognitive Services](https://learn.microsoft.com/azure/governance/policy/samples/built-in-initiatives#cognitive-services)
and the [Foundry Tools policy reference](https://learn.microsoft.com/azure/ai-services/policy-reference#foundry-tools).

## What it is not

It is **not** a way to apply controls at a Foundry-resource, project, deployment, or
agent scope. The Foundry portal assigns policy only at **subscription** or **resource group**
scope. To configure controls on a specific model deployment or agent, use
**Build → Guardrails** instead.

It is also **not** an audit log or runtime blocker for unsafe input or output. It can
require that a deployment's guardrail is configured to annotate or block, then audit
whether the deployment's **configuration** meets that requirement. The guardrail/content
filter does the actual detection and blocking at inference time. For app-level
enforcement outside Foundry guardrails, call **Azure AI Content Safety** from the
application.
