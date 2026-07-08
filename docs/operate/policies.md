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
> deployment in **Build → Guardrails** (not the
> [Compliance Guardrails tab](guardrails.md)); that runtime layer is backed by
> [Azure AI Content Safety](https://learn.microsoft.com/azure/ai-services/content-safety/overview)
> and is **GA**.

References:
[Manage compliance and security](https://learn.microsoft.com/azure/foundry/control-plane/how-to-manage-compliance-security),
[Create a guardrail policy](https://learn.microsoft.com/azure/foundry/control-plane/quickstart-create-guardrail-policy),
[Guardrails overview](https://learn.microsoft.com/azure/foundry/guardrails/guardrails-overview).

## What it is

The Foundry portal's **Create policy** page is an
**[Azure Policy](https://learn.microsoft.com/azure/governance/policy/overview)**-backed
configuration-governance surface: creating or editing policies requires the **Resource
Policy Contributor** or **Owner** role, and the selected controls map to built-in Azure
Policy definitions. Microsoft Learn says deleting a Foundry policy removes the underlying
Azure Policy assignment; live testing confirmed that the portal-created policy appears as
an assignment of the built-in guardrail initiative.

**Scope is subscription or resource group only.** The scope step offers just
**Subscription** and **Resource group** — you *cannot* target an individual Foundry
resource (the Cognitive Services account), project, deployment, or agent from this
Foundry portal page.

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

**Scan results are not immediate.** After creating or editing a policy, the Policies
table can show **No scan results** before Azure Policy evaluates the scope. Expect
**tens of minutes**, not seconds: Microsoft Learn says to allow up to **30 minutes** for
a guardrail policy to appear in the Foundry portal, and Azure Policy's normal compliance
cycle can take up to **24 hours**. Treat **No scan results** shortly after creation as
"not evaluated yet," not as compliant or noncompliant.

Reference:
[Azure Policy built-in initiatives — Cognitive Services](https://learn.microsoft.com/azure/governance/policy/samples/built-in-initiatives#cognitive-services)
and the [Foundry Tools policy reference](https://learn.microsoft.com/azure/ai-services/policy-reference#foundry-tools).

### Example: Hate / User input

For **Hate** at the **User input** intervention point, the two action choices map to
different configuration requirements:

| Portal action | Requirement on the deployment's content filter |
| --- | --- |
| **Annotate and block** | Hate prompt filter is enabled, and `blocking` must be `true` |
| **Annotate only** | Hate prompt filter is enabled; `blocking` may be `true` or `false` |

In Azure Policy parameters, that distinction appears as:

| Portal action | Relevant parameters |
| --- | --- |
| **Annotate and block** | `allowedHateEnabledForPrompt = ["true"]`, `allowedHateBlockingForPrompt = ["true"]` |
| **Annotate only** | `allowedHateEnabledForPrompt = ["true"]`, `allowedHateBlockingForPrompt = ["true", "false"]` |

A deployment using `Microsoft.DefaultV2` has the Hate prompt filter enabled with
`blocking=true`, so both example policies evaluate as compliant.

After scan results arrive, the **Policies** tab shows one row per policy (for example,
**No violations**, total assets `2`, assets in violation `0`). The inner **Assets** tab
shows one row per `(asset, policy)` pair; two model deployments evaluated against two
policies appear as four **No violations** rows.

**Dated observation (2026-07-08): portal rows can differ from raw Azure Policy state.**
Two policy experiments produced raw Azure Policy `NonCompliant` member states for the
parent `Microsoft.CognitiveServices/accounts` resource, while the Foundry **Policies** tab
showed **No violations**, total assets `2`, assets in violation `0`. The inner **Assets**
tab showed model-deployment rows only. This was observed for **Spotlighting** and
**Protected material for code** policies. This might be a portal aggregation issue, a
preview limitation, or a misunderstanding of how this surface maps raw policy state to
Foundry assets. Public feedback issue:
[microsoft-foundry/new-foundry-portal#133](https://github.com/microsoft-foundry/new-foundry-portal/issues/133).

## What it is not

It is **not** a way to apply controls at a Foundry-resource, project, deployment, or
agent scope. The Foundry portal assigns policy only at **subscription** or **resource group**
scope.

It is also **not** an audit log or runtime blocker for unsafe input or output. It can
require that a deployment's guardrail is configured to annotate or block, then audit
whether the deployment's **configuration** meets that requirement. For controls at a
specific deployment, agent, app, or request boundary, use the runtime enforcement layer
instead: **Build → Guardrails** for Foundry-managed models/agents, or **Azure AI Content
Safety** directly from application code when you own the enforcement path.
