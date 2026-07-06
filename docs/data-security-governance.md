# Foundry "Data security and governance": what it governs, and what it doesn't

> **Preview (as of 2026-07-06).** The "Data security and governance" pane is the
> Foundry portal's Microsoft Purview integration, which Microsoft's own docs mark as
> **(preview)** — see the section
> [Enable enterprise-grade data security and compliance for Foundry with Microsoft Purview (preview)](https://learn.microsoft.com/azure/foundry/control-plane/how-to-manage-compliance-security#enable-enterprise-grade-data-security-and-compliance-for-foundry-with-microsoft-purview-preview).
> It has no SLA and isn't recommended for production. Behavior may change.
>
> **The portal doesn't make this obvious.** As of 2026-07-06, the Foundry portal
> shows a "Preview" badge on the Compliance workspace's *Policies* view but **not**
> when the *Data security and governance* tab is selected — so the pane itself carries
> no visible preview label (verified live in the portal). Treat it as preview
> regardless, per the docs above.
>
> **Want GA today? Use Azure AI Language PII instead of this pane.** To block or audit
> sensitive info on generally-available technology, call
> [Azure AI Language PII detection](https://learn.microsoft.com/azure/ai-services/language-service/personally-identifiable-information/overview)
> from your app: **block** = refuse/redact on a hit; **audit** = detect-only and log
> hits (e.g. to Azure Monitor / Log Analytics). This pane is only preferable when you
> specifically want turnkey, admin-defined, org-wide compliance governance (unified
> audit log, insider-risk, eDiscovery, retention) with no app code — and accept
> preview.

The Microsoft Foundry portal exposes a **Microsoft Purview integration** under
**Operate → Compliance**. Its framing ("enforce Data Loss Prevention policies",
"monitor sensitive data flowing through AI agents") is easy to misread as: *enabling
it makes an agent withhold confidential documents from users who shouldn't see them
during RAG.* It does not do that. This note draws the boundary so you can pick the
right control for your goal.

For the authoritative references, see
[Manage compliance and security in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/control-plane/how-to-manage-compliance-security)
and [Use Microsoft Purview to manage data security & compliance for Microsoft Foundry](https://learn.microsoft.com/purview/ai-azure-foundry).

## What it is

A toggle that connects Foundry **interaction data** (prompts and responses) to your
tenant's Microsoft Purview (DSPM for AI), then applies Purview capabilities to that
data:

- **Interaction-level monitoring and audit** — prompts/responses captured in the
  unified audit log and surfaced in DSPM for AI Activity Explorer.
- **Insider-risk detection** and other DSPM/compliance solutions over AI usage.
- **Data loss prevention** — today, support is limited to a DLP policy that **blocks
  prompts by sensitive-information-type** (configured via a PowerShell cmdlet scoped
  to an Entra-registered AI app).

Notes:

- Enabling the Purview integration requires the **Foundry Account Owner** role;
  applying Purview policies requires pay-as-you-go billing in the tenant.
- Purview **data security policies** apply to API calls that carry user context (an
  Entra ID user-context token). Other authentication scenarios get audit and
  classification only.

### Use cases

All of these run on **one detection engine**: with the pane on, Microsoft Purview
classifies Foundry interaction data (prompts and responses) by
**sensitive-information-type** (SSN, credit card, My Number, …). What differs is the
**outcome** you attach to a match — *audit* it or *block* it. Both are **preview**,
and neither is yet exercised end-to-end here (blocked by tenant licensing — see
`purview-dspm-access.md`). Both need **tenant-admin** setup (privileges below) and are
enabled mostly **off ARM**: the Foundry→Purview toggle is a portal (private BFF)
action and the policy/onboarding live on the **Purview/compliance plane**, so none of
it is settable in Bicep.

- **Audit the match** *(visibility — record it)*. The prompt/response is captured in
  the unified audit log and DSPM for AI Activity Explorer. Included in the
  **Microsoft Purview license** (no pay-as-you-go), works for **all** authentication
  scenarios, and needs no per-app setup. Nothing is stopped.
- **Block the prompt (DLP)** *(prevention — stop it)*. A Purview DLP policy stops
  prompts matching a sensitive-information-type. Adds requirements over audit:
  **pay-as-you-go billing**; only fires on API calls carrying a **user-context
  token**; and per-app wiring — a PowerShell cmdlet scoped to an Entra-registered AI
  app, whose app calls `processContent` (Microsoft Graph) to honor the verdict.
  - *Purview DLP vs. Azure AI Language PII:* both recognize SSN-type data via
    **independent** engines — choose by operating model, not by "who can spot an SSN."
    Use **Azure AI Language PII** for a developer API your app calls to detect/redact
    PII, where the app owns the action (per-app, in code, no org policy or audit).
    Use **Purview DLP** (this pane) for an admin-defined, tenant-wide compliance
    policy with centralized enforcement and an audit trail.

A sensitivity **label** on retrieved content is only ever **audited/classified** by
this pane — it is never used to block a prompt. Preventing *labeled* data from being
returned is a different mechanism entirely (see *What it is not*, below).

### Testing: privileges required

> The Purview cases (DLP block, audit) are **not yet verified end-to-end** — they are
> blocked in this environment by tenant licensing (see `purview-dspm-access.md`).

Both use cases (DLP block, audit) require **tenant-admin roles — a developer cannot
self-serve**:

- Turning on **DSPM for AI** (the prerequisite for both) requires an Entra
  **Compliance Administrator** / **Global Administrator** or a **Purview Compliance
  Administrator** role.
- Applying Purview policies requires **pay-as-you-go billing** associated to the
  tenant (billing / subscription-owner rights). Without it, only audit is available.
- The DLP block additionally needs: creating an **Entra app registration** (tenants
  often restrict this to an **Application Developer**/admin role), **admin consent**
  for its Microsoft Graph permissions (a privileged directory admin), and
  **Security & Compliance PowerShell** access (Compliance Administrator).
- Subscription **Contributor** alone is insufficient for any of the above.

## What it is not

It is **not** the mechanism that decides which retrieved documents a specific user is
allowed to see in a RAG response. Toggling it on does not trim search results per
user — that authorization check happens elsewhere.

### The control that does per-user retrieval trimming

Per-user trimming of retrieved knowledge is enforced inside **Azure AI Search** at
query time (under the caller's Microsoft Entra identity), **not** by the Foundry
governance pane. It underpins Foundry IQ, and there are two paths:

- **Document-level ACLs / RBAC scope** — indexed knowledge sources carry Entra
  user/group permissions (natively from sources like ADLS Gen2, or pushed into
  permission fields); results are filtered by the caller's identity. This path needs
  **no** Microsoft Purview. See
  [Document-level access control in Azure AI Search](https://learn.microsoft.com/azure/search/search-document-level-access-overview).
- **Microsoft Purview sensitivity labels** — for an encrypted item the querying user
  must hold the **EXTRACT** usage right (plus **VIEW**) for it to be returned. See
  [Query-Time Microsoft Purview Sensitivity Label Enforcement in Azure AI Search](https://learn.microsoft.com/azure/search/search-query-sensitivity-labels)
  (AI Search `2026-05-01-preview`, **preview**) and
  [Sensitivity labels and AI interactions](https://learn.microsoft.com/purview/ai-azure-foundry#sensitivity-labels-and-ai-interactions).

## Verified in the portal vs. documented

- **Verified in the live portal (2026-07-06):** the Purview enablement toggle exists
  under **Operate → Compliance → Data security and governance** (a Preview pane). The
  sibling **Security posture** tab there is Microsoft Defender for Cloud, not this
  Purview surface — the two coexist.
- **From documentation only:** the specific capability behaviors, the DLP
  "blocks prompts by sensitive-information-type" limitation, and the EXTRACT/VIEW
  query-time enforcement in Azure AI Search — see the linked Microsoft Learn pages
  above. (The Foundry Account Owner role requirement and preview status are stated
  in the portal itself.)
