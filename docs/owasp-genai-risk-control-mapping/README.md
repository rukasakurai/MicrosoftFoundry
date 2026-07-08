# OWASP GenAI Risk → Microsoft Control Mapping

> _Point-in-time technical capability analysis for planning purposes — not an evaluation, benchmark, or criticism of any product. Capabilities change quickly; re-verify before relying on any cell._

This document maps the **OWASP Top 10 for LLM Applications (2025)** and the **OWASP Top 10 for
Agentic Applications (2026)** against the controls available in **Microsoft Foundry** and the
surrounding Microsoft security stack. For each risk it records:

1. Whether **Foundry** appears to provide a way to manage the risk.
2. Whether a partial/missing control is a **Foundry product gap** or a risk that is **legitimately
   owned by another layer** (shared responsibility).
3. Which Microsoft product **should** own the control.

> This is a **working analysis meant to be iterated on**, not an official Microsoft control matrix.
> Treat every "Foundry control" cell as a point-in-time hypothesis. The portal observations below are
> evidence, not a complete survey of every REST API, SDK, ARM/Azure Policy surface, or private preview.

## How this was verified

- **Method:** product-surface review, including live navigation of the Foundry portal "New Foundry"
  experience using Playwright MCP. See the
  [`foundry-ui-playwright`](../../.github/skills/foundry-ui-playwright/SKILL.md) skill for portal
  navigation and re-verification steps.
- **Environment:** a non-production Foundry resource (`Microsoft.CognitiveServices/accounts`, kind
  `AIServices`). No environment identifiers are recorded here by design.
- **Last verified:** 2026-06-15.
- **Caveat:** Several of the strongest Foundry controls are in **Preview**, and **Evaluations** was
  RBAC-gated in the test account. Re-confirm before relying on any single cell.

## Legend

**Primary owner / Supporting:** planning hypotheses for the relevant control slice, not authoritative
compliance assignments.

## Foundry portal controls observed (2026-06-15)

- **Build → Guardrails → Create:** Jailbreak, Indirect prompt injections, Spotlighting (Preview),
  Content harms (Hate/Sexual/Self-harm/Violence), Blocklists, Protected material (code/text),
  PII (Preview; input / tool-call / tool-response / output), Task adherence "task drift" (Preview, on tool call).
- **Operate → Compliance:** Policies (mandate minimum guardrail controls per scope), Guardrails
  (fleet view), Security posture (Defender for Cloud recommendations), Data security & governance
  (Microsoft Purview integration).
- **Build → Tools:** MCP/custom tool auth — Key-based, OAuth Identity Passthrough, Microsoft Entra, Unauthenticated.
- **Other surfaces:** Build → Evaluations (RBAC-gated in test env), Build → Memory, Operate → Quota,
  Operate → Assets (Agents/Models/Tools inventory), Operate → Admin (projects/users/RBAC).

## OWASP Top 10 for LLM Applications (2025)

| # | Risk | Foundry control | Primary owner | Supporting |
|---|------|-----------------|---------------|------------|
| LLM01 | Prompt Injection | Direct: Guardrails for Jailbreak, Indirect prompt injections, and Spotlighting; enforce via Compliance Policies | **Foundry** | Defender for AI, APIM |
| LLM02 | Sensitive Information Disclosure | Direct: Guardrails PII; Compliance Purview DLP/sensitive-data monitoring | **Purview** + Foundry + Entra (access slice) | Azure AI Search (RAG trimming), Defender |
| LLM03 | Supply Chain | Partial/shared: Operate → Assets registry + Security posture (Defender) recs | **Other** (GHAS, Azure Policy) + **Defender for Cloud** (vuln) | Azure API Center (leads API/tool/MCP inventory + allow-listing), APIM (runtime), Purview (model/data lineage), Foundry |
| LLM04 | Data and Model Poisoning | No dedicated Foundry control observed; Build → Data/Knowledge governance + Purview are indirect | **Purview** + Foundry | Azure AI Search (index provenance/RBAC), Other (model provider, Storage immutability) |
| LLM05 | Improper Output Handling | Partial: output-side guardrails reduce bad output; downstream validation/sanitization is app-side | **Other** (app code / GHAS) | APIM, Foundry, Entra (blast-radius containment) |
| LLM06 | Excessive Agency | Partial: Task adherence guardrail and tool auth scoping; action authorization/rate control live elsewhere | **Entra** + Foundry | APIM, Azure API Center (curated/approved tool catalog) |
| LLM07 | System Prompt Leakage | No dedicated control observed; Jailbreak/Spotlighting help indirectly | **Other** (architecture, Key Vault) | Entra (managed identity ⇒ no secrets in prompt), Foundry, Defender |
| LLM08 | Vector and Embedding Weaknesses | No dedicated vector/embedding control observed beyond RBAC on Knowledge/Data connections | **Azure AI Search + Entra** | Purview (classification/labels), Private Link |
| LLM09 | Misinformation | Partial: Evaluations for groundedness/relevance; RBAC-gated in test env | **Foundry** | Azure AI Search (retrieval quality/provenance), Other (human review) |
| LLM10 | Unbounded Consumption | Partial/monitoring: Operate → Quota (deployment capacity) + Overview usage monitoring | **API Management** + Foundry | Defender/Monitor, Entra |

## OWASP Top 10 for Agentic Applications (2026)

| # | Risk | Foundry control | Primary owner | Supporting |
|---|------|-----------------|---------------|------------|
| ASI01 | Agent Goal Hijack | Direct: Guardrails for Indirect prompt injections, Jailbreak, and Task adherence | **Foundry** | Defender for AI, Sentinel |
| ASI02 | Tool Misuse & Exploitation | Partial: Task adherence guardrail on tool calls, PII on tool call/response, and tool auth | **API Management** + Foundry | Entra, Defender, Azure API Center (vetted tool/MCP registry + allow-listing) |
| ASI03 | Agent Identity & Privilege Abuse | Partial: Build → Tools auth + Operate → Admin RBAC; identity lifecycle is Entra-owned | **Entra** | Sentinel (UEBA), Defender for Identity |
| ASI04 | Agentic Supply Chain Compromise | Partial/shared: Assets registry, Security posture (Defender) recs, and connection governance | **Azure API Center** (MCP/tool registry, allow-listing) + **Defender for Cloud** + Other (GHAS, Azure Policy) | Foundry, APIM |
| ASI05 | Unexpected Code Execution | Platform-managed sandbox; no operator config observed | **Foundry** (sandbox) + Defender | Other (container/network isolation) |
| ASI06 | Memory & Context Poisoning | Partial: Indirect prompt injection guardrail for tool-response ingestion; Memory has no poisoning control observed | **Foundry** | Azure AI Search (retrieved-context provenance/partitioning), Purview, Other |
| ASI07 | Insecure Inter-Agent Communication | No dedicated Foundry control observed for A2A channel security | **API Management + Entra** | Other (Private Link, mTLS), Foundry, Azure API Center (A2A/MCP endpoint inventory) |
| ASI08 | Cascading Agent Failures | Monitoring only: Operate → Overview (health/alerts/anomalies) + Quota | **API Management** + Foundry | Sentinel, Azure Monitor |
| ASI09 | Human-Agent Trust Exploitation | Indirect only: content-harm/groundedness controls reduce deceptive output; UX owns the main risk | **Other** (UX, training, provenance labels) | Foundry, Purview |
| ASI10 | Rogue / Shadow Agents | Partial: Assets inventory, Overview agent discovery, Admin, and Defender detection | **Sentinel + Defender for Cloud** | Entra (Agent ID inventory), Foundry, Azure API Center (sanctioned-tool baseline + Dev Proxy shadow detection) |

## Product ownership — role of each layer

| Product | Remit for these risks |
|---------|-----------------------|
| **Foundry** | In-context AI controls: guardrails, groundedness/evaluations, memory, code-interpreter sandbox, asset inventory |
| **Entra ID** | Agent identity (Entra Agent ID), RBAC, Conditional Access, PIM, managed identities |
| **Azure AI Search** | RAG retrieval substrate: index schema, retrievable fields, ACL/RBAC trimming, vector/hybrid retrieval, semantic configuration, and Search data-plane RBAC |
| **API Management** (GenAI Gateway) | Runtime traffic: token rate-limits, quotas/cost caps, throttling, tool & A2A mediation, circuit breakers |
| **API Center** | Design-time supply-chain governance: org-wide inventory of APIs/tools/MCP servers, allow-listing via metadata, versioning/lifecycle, API-definition linting — **not** runtime enforcement or vuln scanning |
| **Purview** | Data plane: classification, DLP, insider risk, lineage, audit/compliance |
| **Sentinel** | SIEM/SOAR: cross-estate detection, correlation, hunting, incident response |
| **Defender** (for Cloud / AI / XDR) | Posture management (CSPM) + runtime AI threat detection/alerts |
| **Intune** | Device/endpoint compliance — **not a primary owner** for any of the 20; only a Conditional Access signal feeding Entra |
| **Other** | App code / secure SDLC, GitHub Advanced Security, Azure Policy, Key Vault, networking (Private Link), model provider |

## Synthesis

- **Foundry's natural lane (primary on ~5):** LLM01, LLM09, ASI01, ASI05, ASI06 — the in-context AI controls.
- **Entra (primary/co on ~5):** LLM02, LLM06, LLM08, ASI03, ASI07 — who/what an agent is and what
  sensitive data it may reach. The
  **Entra Agent ID** story is the biggest cross-cutting dependency.
- **Azure AI Search (primary/co on ~1, material support on RAG risks):** LLM08, plus LLM02/04/09 and
  ASI06 when retrieved knowledge is in scope — where RAG access, provenance, and vector behavior live.
- **API Management (primary/co on ~4):** LLM10, ASI02, ASI07, ASI08 — runtime traffic, cost, and
  mediation. An easy layer to overlook when planning for agentic risk.
- **Purview (primary/co on ~2):** LLM02, LLM04 — the data classification, DLP, and lineage plane.
- **Sentinel + Defender (primary/co on ~4):** ASI04, ASI05, ASI10, plus detection support on
  ASI01/03/08 — the detect-and-respond plane; nothing else discovers shadow agents across the estate.
- **Other / SDLC (primary on ~4):** LLM03, LLM05, LLM07, ASI09 — code, architecture, and human-factor risks.

**Takeaway:** a defensible governance story needs multiple planes, not just Foundry —
Foundry (in-context safety) + Entra (agent identity) + Azure AI Search (RAG retrieval) + APIM
(runtime traffic/cost) + Purview (data) + Sentinel/Defender (detect & respond). Most missing or
partial Foundry controls for LLM06, LLM10, ASI02, ASI07, ASI08, and ASI10 are
**intentional hand-offs** to those layers — *provided* you have actually deployed and wired them.
Foundry's Operate/Compliance tab covers the in-context slice; the rest of the story lives in the
adjacent layers. The Foundry-owned limitations cluster in the **agentic-era** controls (tool agency, memory,
multi-agent comms, consumption/cost, rogue agents), which extend beyond the content-safety controls
Foundry covers most strongly today.

## Per-product deep dives

Use these deeper notes for inspiration only:

- [Azure API Center](./api-center.md)
- [Microsoft Entra ID (incl. Agent ID)](./entra.md)

> ⚠️ Facts in these pages may be stale or wrong. Risk mitigation decisions are highly context dependent,
> so do not apply the analysis naively; re-check the product behavior and threat model for the specific
> deployment.

## Known unknowns

- Do any "no dedicated control observed" rows have documented public REST, SDK, ARM/Bicep, or
  Azure Policy controls not visible in the portal? Verify only against public docs and authorized
  non-production resources.
- Are the ASI01–ASI10 names aligned with the final OWASP Agentic Applications list? If the OWASP names
  are still draft, cite the draft source rather than treating the labels as final.
- Are the RBAC-gated or Preview Foundry controls still represented accurately, especially Evaluations,
  Spotlighting, indirect prompt injection, PII, and Task adherence?

When validating these, use synthetic data and sanitized evidence only. Do not publish tenant-specific
policy names, privileged role assignments, exception groups, break-glass paths, private-preview details,
customer data, raw logs, system prompts, secrets, or real tool responses.
