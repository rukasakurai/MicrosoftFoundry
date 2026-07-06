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

<!-- BEGIN governance-controls map (candidate scope expansion; may be excised) -->
## Where this fits: other Foundry governance controls

The Purview pane is one of several governance controls for a Microsoft Foundry
(`Microsoft.CognitiveServices/accounts`, kind `AIServices`) deployment. This map
situates it. Each entry is tagged by how far it's been confirmed: **Verified** (confirmed
against the `Microsoft.CognitiveServices` ARM provider and this repo's IaC),
**Documented** (Microsoft Learn only), **Untested** (mechanism exists but end-to-end
behavior not exercised).

| Control | What it governs | Where it lives | Status |
| --- | --- | --- | --- |
| Purview "Data security and governance" pane | Interaction-level audit, insider-risk, DLP-by-SIT (see above) | Operate → Compliance | Verified (pane); DLP/audit behavior Untested |
| Per-user RAG trimming | Which retrieved documents a user may see | Azure AI Search (ACL/RBAC or Purview labels) | Documented |
| Network isolation | Whether the data plane is reachable from the public internet | Account `publicNetworkAccess` + private endpoint | Verified (repo sets `Enabled`); isolation Untested |
| Key vs. Entra-only auth | Whether non-Entra key auth is accepted | Account `disableLocalAuth` | Repo Bicep does not set it (key auth enabled by default on deploy); set it to enforce Entra-only |
| Foundry RBAC roles | Management vs. use (not a data-access tier) | Foundry built-in roles / role assignments | Verified — User & Project Manager have full data-plane; Account Owner has none |
| Content filtering (responsible AI) | Model prompt/response content filtering | `accounts/raiPolicies` on the deployment | Documented mechanism; Untested |
| Diagnostic / audit logging | Audit trail of resource + interaction activity | Diagnostic settings → Log Analytics | Verified categories (`Audit`, `RequestResponse`, `Trace`, `AzureOpenAIRequestUsage`) |
| Azure Policy compliance | Posture enforcement/audit (backs the portal's Defender recommendations) | Built-in `Microsoft.CognitiveServices` policies | Verified availability |

Running these as experiments is tracked separately as issues, not in this reference.

<!-- END governance-controls map -->

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

<!-- BEGIN governance use-case groups (candidate scope expansion; may be excised) -->
## Governance use cases, grouped by profile

Candidate experiments for exploring Foundry governance, grouped so that use cases
sharing a **required-privilege**, **cost**, and **purpose** profile sit together.
The grouping matters because it predicts *who* can run an experiment and *what* it
costs before any work starts. Status tags (Verified / Documented / Untested) carry
the same meaning as the controls map above.

### Group 1 — Interaction governance via Microsoft Purview
- **Purpose:** govern the *interaction* (prompts/responses) for compliance.
- **Privilege:** tenant admin — Entra Compliance/Global Admin or Purview Compliance
  Admin to turn on DSPM, plus billing rights; DLP also needs Graph admin consent and
  Security & Compliance PowerShell. Not self-serviceable by a developer.
- **Cost:** Microsoft Purview pay-as-you-go meters (distinct, less predictable);
  the DLP block test also stands up a serverless app (Functions + Cosmos DB + Static
  Web App + Azure OpenAI).
- Purview DLP: block a prompt by sensitive-information-type (needs an instrumented
  Entra-registered app). *Documented; behavior Untested.*
- Purview audit/monitoring of AI interactions (DSPM for AI Activity Explorer).
  *Documented; behavior Untested.*

### Group 2 — Per-user knowledge (RAG) governance
- **Purpose:** control which retrieved documents a specific user may see.
- **Privilege:** mostly developer-doable, but the *test* needs a second Entra
  identity (service principal) and possibly group management; app-registration may be
  restricted in locked-down tenants. No tenant-compliance admin required for the
  ACL/RBAC path.
- **Cost:** an Azure AI Search service (free tier + free agentic-retrieval token
  allocation available for POC) plus inference tokens.
- Foundry IQ per-user retrieval trimming and knowledge grounding, via Azure AI Search
  document-level ACL/RBAC (Purview-free) or Purview sensitivity labels. *Documented.*

### Group 3 — Authorization & posture (elevated Azure RBAC, free)
- **Purpose:** control-plane authorization and posture enforcement.
- **Privilege:** beyond plain Contributor — role assignments need Owner or User
  Access Administrator; policy assignment needs Owner or Resource Policy Contributor.
- **Cost:** effectively free (assignments/assessments, no billable resource).
- Foundry RBAC boundary: management-vs-use, not a data tier (User & Project Manager
  have full data-plane; Account Owner has none). *Verified (role definitions).*
- Azure Policy compliance for `Microsoft.CognitiveServices` (backs the portal's
  Defender recommendations). *Verified availability.*

### Group 4 — Resource hardening (developer / Contributor, config-only)
- **Purpose:** harden the Foundry resource itself.
- **Privilege:** Contributor on the resource is enough (exception: *loosening*
  default content filters requires a Microsoft approval process).
- **Cost:** config-only or minor (Key Vault for CMK; Log Analytics ingestion by
  volume — the repo provisions a workspace by default, unless observability is
  disabled).
- Disable local/key auth to enforce Entra-only (`disableLocalAuth`). *Verified mechanism.*
- Diagnostic/audit logging to Log Analytics (`Audit`, `RequestResponse`, `Trace`,
  `AzureOpenAIRequestUsage`). *Verified categories.*
- Content filtering / responsible-AI policy on the deployment (`accounts/raiPolicies`).
  *Documented mechanism; Untested.*
- Customer-managed key encryption. *Documented mechanism; Untested.*

### Group 5 — Network perimeter
- **Purpose:** control whether the data plane is reachable from the public internet.
- **Privilege:** Contributor can flip `publicNetworkAccess`, but real private-endpoint
  isolation usually needs a central networking team (shared VNet / private DNS zones).
- **Cost:** a private endpoint (hourly + data processing), typically plus a VNet and a
  vantage host to verify the private round-trip.
- Network isolation: disable public access + add a private endpoint. *Verified default
  (`Enabled`); isolation Untested.*

<!-- END governance use-case groups -->

