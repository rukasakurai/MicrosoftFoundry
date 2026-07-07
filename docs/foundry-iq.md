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
> Foundry reaches them through a **connection**. Whether — and how far — this repo provisions
> any of this is an open scope decision ([#31](https://github.com/rukasakurai/MicrosoftFoundry/issues/31)),
> not yet made. See the [Technology Reference](../AGENTS.md#technology-reference).

<!-- TODO: Elaborate on the difference between the "Plain Azure AI Search" approach
(the single-shot `azure_ai_search` agent tool: the agent's model issues one query
against a search index) and the "Foundry IQ" approach (a managed knowledge base that
performs server-side agentic retrieval — query planning/decomposition, parallel
keyword/vector/hybrid search, semantic reranking — reached by the agent via the
`knowledge_base_retrieve` MCP tool). Only the Foundry IQ approach is (partially) in
this repo's scope; the plain AI Search tool is out of scope. -->
