# Foundry "Data security and governance": what it governs, and what it doesn't

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
- These capabilities are in **preview** at time of writing.

## What it is not

It is **not** the mechanism that decides which retrieved documents a specific user is
allowed to see in a RAG response. Toggling this pane does not trim search results
per user — it monitors and governs the *interaction*, not the *retrieval
authorization*.

## The control that does per-user retrieval trimming

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

## Use cases for this pane

Things you can do *with the Data security and governance pane* (all Microsoft
Purview / DSPM for AI). Both are **preview**; status tags mark how far each is
confirmed (Documented = Microsoft Learn only; behavior not yet exercised end-to-end).

- **Block a prompt by sensitive-information-type (DLP).** A Purview DLP policy that
  stops prompts matching a sensitive-information-type. *Documented; behavior Untested.*
  - *Privilege:* tenant admin — Entra Compliance/Global Admin or Purview Compliance
    Admin to turn on DSPM, plus billing rights; also Graph admin consent and Security
    & Compliance PowerShell. Not self-serviceable by a developer.
  - *Cost:* Microsoft Purview pay-as-you-go meters; the block test also stands up an
    instrumented app (Functions + Cosmos DB + Static Web App + Azure OpenAI).
  - *Enablement plane:* mostly **off ARM** — DSPM onboarding and DLP policy on the
    **Purview/compliance plane**; app registration + admin consent on the **Entra
    plane**; the app calls `processContent` on the **data plane** (Microsoft Graph).
    The Foundry→Purview toggle is a portal (private BFF) action, **not** an ARM
    property, so it can't be set in Bicep.
- **Audit / monitor AI interactions.** Prompts/responses captured in the unified
  audit log and DSPM for AI Activity Explorer, plus insider-risk detection over AI
  usage. *Documented; behavior Untested.*
  - *Privilege:* tenant admin (DSPM turn-on + billing), as above.
  - *Cost:* Microsoft Purview pay-as-you-go meters.
  - *Enablement plane:* **Purview/compliance plane** (portal toggle + Purview config);
    ARM only associates a subscription for PAYG billing.

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
