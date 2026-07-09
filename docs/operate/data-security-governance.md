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
> **Live UI drift (2026-07-08).** Microsoft Learn says the Microsoft Purview toggle
> is under **Security posture**, but the live portal still showed a separate
> **Data security and governance** tab. **Security posture** was Microsoft Defender
> for Cloud only, with "Microsoft Defender isn't connected yet" and **Enable in Azure
> Portal** actions.
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
(prompts and responses) to Microsoft Purview / unified DSPM, which classifies it by
**sensitive-information-type** and either **audits** the match or **blocks** the
prompt (DLP). Both are preview, configured off ARM (portal toggle + Purview plane, so
not settable in Bicep), and gated by the access layers below.

In the live lab (2026-07-08), the pane said enabling the toggle sends Foundry model
interaction data to the tenant's Purview account, that the toggle is effective only
if Purview is present in the tenant, and that without Purview pay-as-you-go billing
only **Audit** integration is supported. After approval, turning the toggle on changed
the pane to "Purview covering visibility across 0 agents and 0+ daily interactions
across 1 subscription." No PAYG prompt appeared in Foundry; PAYG remains a separate
Purview-side gate. A synthetic model call succeeded after the toggle was enabled, but
the Purview/DSPM surfaces still showed **Activate Microsoft Purview Audit** as a
required next step. After approval, clicking it opened an activation panel, but the
final **Activate Purview Audit** action failed with "An error occurred. Please try
again later." **Activity explorer** was reachable but showed another gate: "Additional
permissions required. Your role can't view AI Visits or user risk levels," plus "No
data available yet" and a note that detecting activity can take 24 hours or more.
The account had Entra **Compliance Administrator** and **Global Reader**, but not
Global Administrator or Purview/Exchange **Role Management**; in **Settings → Roles
and scopes → Role groups**, only **My permissions** was editable and role-group
management tabs were disabled.

The Purview **Usage center → Pay-as-you-go** page said the Azure subscription wasn't
linked for billing. Opening **Get started** launched a billing-link dialog, but it
remained stuck on "Loading..." while the backend returned `TenantNotFound`,
`hasValidSubscription:false`, `hasEnterpriseAccount:false`, and US-only eligible PAYG
locations. Microsoft Learn says only **Global Administrator** can enable the PAYG
model. After temporary Global Administrator elevation, role-group management unlocked,
the tester was added to **Data Security AI Content Viewers**, and PAYG setup advanced:
the backend accepted provisioning with HTTP `202` and created a
`Microsoft.Purview/tenantAccounts` account in `westus`. The Usage Center later
returned to "Your Azure subscription isn't linked for billing," so tenant provisioning
and subscription billing link are distinct gates. Retrying the link required selecting
a dedicated resource group, replacing the default resource name (the portal rejected
default names), and waiting for `Microsoft.Purview` / `Microsoft.Storage` provider
registration; the portal then created a `Microsoft.Purview/accounts` resource and
showed **Upgrading** while Azure reported it as `Creating`; once provisioning
completed, the portal showed **Congratulations!** and Azure reported the
`Microsoft.Purview/accounts` resource as `Succeeded`.

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
4. **Purview pay-as-you-go billing** for data security policies beyond Audit. The
   live Foundry pane says billing happens in Purview and is based on pay-as-you-go
   meters and policies created there; without PayG, only Audit integration is
   supported.
5. **Purview Audit activation** in the Purview portal before unified DSPM reports
   Microsoft Copilot/agent interactions. In the live lab, the activation action
   failed with a generic retry-later error; after PAYG was linked, the backing
   `EnableUnifiedAuditLogIngestion` call still returned HTTP `500`. The standalone
   Audit page exposed the underlying Exchange Online gate:
   `InvalidOperationInDehydratedContextException` requiring
   `Enable-OrganizationCustomization`. Later, Exchange Online PowerShell showed the
   org was no longer dehydrated and accepted
   `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true`, but immediate
   verification still returned `false`; Microsoft documents up to 60 minutes for the
   change to take effect.
6. **Role Management / Global Administrator** to assign the missing Purview and
   Exchange role groups. Entra Compliance Administrator alone can view DSPM surfaces,
   but can't manage role groups in the Purview portal. Temporary Global
   Administrator elevation unlocked role-group management in the live lab.
7. **Purview viewing permissions** for Activity Explorer detail such as AI Visits and
   user risk levels. Do not add these roles casually; they can expose sensitive
   prompt/response governance data. For prompt/response content, the narrower first
   role is **Data Security AI Content Viewers**.
8. **PAYG tenant registration / subscription link** before data-security policies for
   enterprise AI apps can be configured. Learn says this requires Global
   Administrator and an Azure subscription/resource group in the tenant. In the live
   lab, tenant-account provisioning succeeded before the subscription billing link was
   complete; the billing link then created a `Microsoft.Purview/accounts` Azure
   resource with a non-default name. Successful PAYG link does not imply Audit
   activation has succeeded.
9. **Defender for Cloud AI workload settings** for the unified DSPM remediation
   action **Secure data in Azure AI apps and agents**. The live panel directs users to
   Defender for Cloud **Environment settings → Cloud Workload Protection → AI
   workloads → Enable data security for AI interactions** and says reporting can take
   at least 24 hours. In ARM/API terms this used `Microsoft.Security/pricings/AI`
   with `pricingTier: Standard` and `AIPromptSharingWithPurview: True`.
10. **Unified DSPM setup tasks**. In the live lab, unified DSPM setup completed and
    created/activated the AI collection-policy path even though Audit activation
    remained blocked; the setup dialog said Audit could be turned on later. A
    post-capture synthetic Foundry response verified with
    `verify-agent-run.sh --expect-text`, but Activity Explorer still showed no data
    immediately afterward.
11. **(DLP block only)** additionally: an Entra **app registration**, Microsoft Graph
   **admin consent** for permissions such as `Content.Process.User`, **Security &
   Compliance PowerShell**, and app code/API integration that calls Graph
   `processContent` and honors the Purview verdict.

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
