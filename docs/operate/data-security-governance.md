# Foundry "Data security and governance": what it governs, and what it doesn't

> ⚠️ **This is a preview feature; the facts below will likely change quickly.** Verify
> against the linked Microsoft Learn pages and the live portal before relying on
> anything here.

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

A toggle under **Operate → Compliance** that connects Foundry interaction data
(prompts and responses) to Microsoft Purview (DSPM for AI), which classifies it by
**sensitive-information-type** and either **audits** the match or **blocks** the
prompt (DLP). Both are preview, configured off ARM (portal toggle + Purview plane, so
not settable in Bicep), and gated by the access layers below. Neither is verified
end-to-end here. For a GA alternative, see the note at the top.

### Turning it on: the access gates

Enabling and testing this pane is gated by **several independent layers** — clearing
one doesn't reveal the next:

1. **Foundry Account Owner** (Azure RBAC on the Foundry resource) to flip the
   Foundry→Purview toggle — a portal action, not an ARM/Bicep property.
2. **Compliance / Global / Purview Compliance Administrator** to turn on DSPM;
   subscription **Contributor** is insufficient.
3. **A Microsoft 365 / Purview license — the hard gate.** A tenant with only
   Azure / Power-Platform SKUs is blocked, and **no role fixes it**. The self-serve
   Purview Suite trial can return `NotAvailable` at the tenant/commerce level — even a
   **Global Administrator** cannot self-serve-activate it. *(Observed on a tenant with
   no Microsoft 365 base subscription.)*
4. **(DLP block only)** additionally: an Entra **app registration**, Microsoft Graph
   **admin consent**, **Security & Compliance PowerShell**, and **pay-as-you-go
   billing**.

The takeaway: the highest-value governance tests are the **least** addressable from
this repo's IaC — they hinge on tenant licensing and admin-plane actions Bicep can't
perform.

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
