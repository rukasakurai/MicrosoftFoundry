# Cost risk prioritization

Purpose: identify which OWASP LLM Top 10 and OWASP Agentic Top 10 risks are
materially cost-relevant for this repo's Microsoft Foundry architecture, so PR
reviewers know where to look for cost impact.

This is not a security risk explainer. It is a cost-review checklist.

## Highest priority

- **LLM10: Unbounded Consumption**
  - Why cost-relevant: explicit denial-of-wallet / runaway usage risk.
  - Repo surfaces: model tokens, PTU/GPU-style capacity, agent loops, evaluation
    runs, telemetry, Azure AI Search / Foundry IQ calls, hosted compute, Content
    Safety / guardrails.
  - Review trigger: any PR that increases call volume, loops, fan-out, retention,
    batch evaluation, retries, or default-on workloads.

- **LLM08: Vector and Embedding Weaknesses**
  - Why cost-relevant: most likely architectural cost risk in this repo because
    Foundry IQ / Azure AI Search can drive indexing, embedding, storage, Search SKU,
    retrieval, reranking, and re-indexing costs.
  - Repo surfaces: `enableFoundryIq`, `searchServiceSku`, knowledge sources,
    chunking, embedding generation, metadata extraction, refresh cadence, duplicate
    indexes, tenant/sensitivity partitioning.
  - Review trigger: any PR changing Search, Foundry IQ, knowledge sources,
    chunking/indexing, retrieval depth, or permission-sync behavior.

- **ASI02: Tool Misuse & Exploitation**
  - Why cost-relevant: agents/tools can invoke paid services repeatedly or with
    expensive parameters.
  - Repo surfaces: MCP tools, Foundry IQ `knowledge_base_retrieve`, API gateways,
    external APIs, Search calls, model/tool chains.
  - Review trigger: any PR adding tools, tool permissions, allowed-tools lists,
    approval behavior, retry behavior, or external service calls.

- **LLM06: Excessive Agency**
  - Why cost-relevant: autonomous agents can perform more work than intended,
    including expensive retrieval, tool calls, hosted compute, or workflow execution.
  - Repo surfaces: agent definitions, tool chains, approval gates,
    scheduled/background jobs, hosted compute, memory.
  - Review trigger: any PR increasing agent autonomy, default tool access,
    background execution, or irreversible/bulk actions.

- **ASI01: Agent Goal Hijack**
  - Why cost-relevant: hijacked goals can redirect agents into repeated or expensive
    work.
  - Repo surfaces: agent instructions, tool-use rules, Foundry IQ knowledge-source
    content, prompt injection paths, retry/fallback behavior.
  - Review trigger: any PR changing instructions, retrieval context, tool routing,
    or fail-open behavior.

## Medium priority

- **ASI03: Identity & Privilege Abuse**
  - Cost relevance: over-privileged identities can access or invoke paid resources
    beyond intended scope.
  - Review trigger: broader RBAC, new managed identities, new app registrations,
    admin consent, or tenant-wide permissions.

- **ASI05: Unexpected Code Execution**
  - Cost relevance: code execution can start compute, CI/CD, containers, functions,
    or data processing.
  - Review trigger: only relevant if repo features allow generated/user-controlled
    code execution or tool execution.

- **ASI06: Memory & Context Poisoning**
  - Cost relevance: poisoned memory/context can persistently trigger bloated prompts,
    bad retrieval, or repeated workflows.
  - Review trigger: only relevant if memory/context persistence is introduced.

- **LLM01: Prompt Injection**
  - Cost relevance: indirect, through tool loops, excessive retrieval, or
    denial-of-wallet behavior.
  - Review trigger: new untrusted context, retrieval paths, tool-routing rules, or
    fail-open behavior.

## Low priority / indirect cost only

Treat these primarily as remediation or business-cost risks, not primary Azure meter
risks, unless a PR adds a concrete cost-bearing surface:

- **LLM02: Sensitive Information Disclosure**
- **LLM03: Supply Chain**
- **LLM04: Data and Model Poisoning**
- **LLM05: Improper Output Handling**
- **LLM07: System Prompt Leakage**
- **LLM09: Misinformation**
- Other Agentic Top 10 categories not directly tied to tool fan-out, privilege,
  memory/context, or code execution

For these, avoid long subsections. Note the indirect cost path only when it matters:
incident response, Purview/eDiscovery, reindexing, cleanup, tenant review, or
operational downtime.

## Explicitly out of scope

- Full OWASP risk explanations.
- Full security mitigation guidance.
- Generic AI control prose.
- Customer-facing cost claims.
- Stale pricing numbers.
- Invented quantitative estimates.

## References

- [OWASP Top 10 for LLM Applications](https://genai.owasp.org/llm-top-10/)
- [OWASP Top 10 for Agentic Applications](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)
- [Microsoft Foundry pricing](https://azure.microsoft.com/pricing/details/microsoft-foundry/)
- [Azure AI Search pricing](https://azure.microsoft.com/pricing/details/search/)
- [Azure AI Search / Foundry IQ concepts](https://learn.microsoft.com/azure/foundry/agents/concepts/what-is-foundry-iq)
- [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
