# Foundry IQ (RAG / knowledge base) in this repo

> ⚠️ **Partly preview; the facts below will likely change quickly.** Verify against
> the linked Microsoft Learn pages and the live portal before relying on anything here.

> **GA vs preview is split by API version (as of 2026-07-07).** Per Microsoft's own docs,
> "[Some Foundry IQ features are now generally available, while others remain in preview.
> Availability depends on the Search Service REST API version you use. The Microsoft Foundry
> portal and Azure portal continue to provide preview-only access to all agentic retrieval
> features.](https://learn.microsoft.com/azure/foundry/agents/concepts/what-is-foundry-iq)"
>
> - **GA** — the knowledge base and extractive, minimal agentic retrieval via the Azure AI
>   Search REST API **`2026-04-01`**.
> - **Preview** — the fuller feature set via **`2026-05-01-preview`** (server-side query
>   planning, **answer synthesis**, configurable reasoning effort, and preview knowledge
>   sources such as web and remote SharePoint), plus **both portal UIs** (Foundry and Azure),
>   which are preview-only for all agentic retrieval. Preview features have no SLA and aren't
>   recommended for production. See
>   [Migrate agentic retrieval code to the latest version](https://learn.microsoft.com/azure/search/agentic-retrieval-how-to-migrate).

> **Not an ARM/Bicep provisioning surface.** A Foundry IQ knowledge base and its knowledge
> sources are **Azure AI Search data-plane** objects (`Microsoft.Search`), created via the AI
> Search REST API / SDK / portal — not ARM/Bicep and not the `CognitiveServices` provider.
> Foundry reaches them through a **connection**. This repo treats the **Foundry IQ**
> path (the managed knowledge base) as in scope and the plain `azure_ai_search` tool as
> out of scope (see the last section); **how far** it provisions the Foundry IQ
> substrate — e.g. a Foundry→AI Search connection — is still open
> ([#31](https://github.com/rukasakurai/MicrosoftFoundry/issues/31)). See the
> [Technology Reference](../AGENTS.md#technology-reference).

## Per-user data governance is not GA (verified 2026-07-07)

Per-user retrieval trimming (returning only the documents a given caller may see) —
the "control that does per-user retrieval trimming" in
[data-security-governance.md](operate/data-security-governance.md) — is **not generally
available** for Foundry IQ.

- **Identity-native enforcement is preview only.** Azure AI Search
  [document-level access control](https://learn.microsoft.com/azure/search/search-document-level-access-overview)
  has four approaches; only **security filters** (an app-built `$filter` string) are
  "API-agnostic, generally available". The identity-native paths — **POSIX-like ACL /
  RBAC scopes**, **Microsoft Purview sensitivity labels**, and **SharePoint ACLs** —
  are all **`2026-05-01-preview`**. Verified: a `permissionFilterOption` index is
  **rejected on the GA `2026-04-01` API** ("property does not exist in API version
  2026-04-01") and accepted only on `2026-05-01-preview`.
- **The one GA path doesn't flow per-user through a managed agent.** The GA
  `2026-04-01` `$filter` trims correctly (verified), but the caller identity is passed
  by *your* query code, and a Foundry IQ agent's tool filter is static per agent
  version — not per caller. Microsoft's own docs add that
  "[Foundry Agent Service doesn't support per-request headers for MCP tools ... For
  per-user authorization, use the Azure OpenAI Responses API instead](https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect)",
  so the preview `x-ms-query-source-authorization` per-user token can't ride a managed
  Foundry IQ agent either.

Bottom line: to enforce per-user document access **GA** today, do security-filter
trimming in your own retrieval code (Responses API), not through a managed Foundry IQ
agent; the identity-native, turnkey enforcement is preview.

## How Foundry IQ retrieval differs from the plain Azure AI Search tool

Two ways an agent can ground on Azure AI Search; only the first is in this repo's scope.

- **Foundry IQ (in scope)** — a managed **knowledge base** performs *server-side
  agentic retrieval*: it plans and decomposes the query into subqueries, runs them
  in parallel (keyword / vector / hybrid), semantically reranks, and returns a
  unified, cited result. The agent reaches it via the generic `mcp` tool
  (`knowledge_base_retrieve`). Trace: `mcp_list_tools → knowledge-base → message`.
- **Plain Azure AI Search (out of scope)** — the native `azure_ai_search` agent
  tool: the agent's model issues a **single** query against one search index and
  synthesizes the `top_k` results itself, with no server-side planning or reranking.
  Trace: `azure_ai_search_call → message`.

Same substrate (`Microsoft.Search`, data-plane, reached via a connection), but
different retrieval mechanisms — not just a rename. See
[Connect an Azure AI Search index to Foundry agents](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search)
and [Connect agents to Foundry IQ knowledge bases](https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect).

## Applying the Foundry IQ connect guidance to CognitiveServices projects (verified 2026-07-07)

Microsoft's
[Foundry IQ connect guidance](https://learn.microsoft.com/azure/foundry/agents/how-to/foundry-iq-connect)
writes its connection examples for **hub/workspace** projects
(`Microsoft.MachineLearningServices/workspaces`). This repo uses **Microsoft Foundry**
(`Microsoft.CognitiveServices`) projects instead, and two things are worth recording
from adapting the guidance to that project type (the doc isn't wrong for its own
context — these are observations specific to the `CognitiveServices` form):

- **The connection also works on a `CognitiveServices` project.** The doc's examples
  create the connection under
  `Microsoft.MachineLearningServices/workspaces/.../connections` (api-version
  `2025-10-01-preview`). The same `RemoteTool` / `ProjectManagedIdentity` connection
  works as `Microsoft.CognitiveServices/accounts/projects/connections` (api-version
  `2026-05-01`), which is what this repo provisions in Bicep.
- **On the `CognitiveServices` connection, `audience` must have _no_ trailing slash.**
  The doc's (hub/workspace) example uses `"audience": "https://search.azure.com/"`. On
  the `CognitiveServices` form, that trailing slash makes the agent fail at run time
  with `Missing required query parameter 'audience'`; `https://search.azure.com` (no
  slash) works. We didn't test whether the slash matters on the hub/workspace form, so
  this is a `CognitiveServices`-specific note, not a claim about the doc's example.
  (Also noted inline in `infra/main.bicep`.)


Both are preview-era observations and may change; re-verify against the live docs.
