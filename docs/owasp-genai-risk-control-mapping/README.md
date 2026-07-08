# OWASP GenAI Risk → Microsoft Control Mapping

> _Point-in-time technical capability analysis for planning purposes — not an evaluation, benchmark, or criticism of any product. Capabilities change quickly; re-verify before relying on any cell._

This document maps the **OWASP Top 10 for LLM Applications (2025)** and the **OWASP Top 10 for
Agentic Applications (2026)** against the controls available in **Microsoft Foundry** and the
surrounding Microsoft security stack. For each risk it records:

1. Whether the **Foundry GUI** provides a way to manage the risk (verified against a live deployment).
2. Whether a partial/missing control is a **Foundry product gap** or a risk that is **legitimately
   owned by another layer** (shared responsibility).
3. Which Microsoft product **should** own the control.

> This is a **working analysis meant to be iterated on**, not an official Microsoft control matrix.
> Treat every "Foundry GUI" cell as a point-in-time observation that should be re-verified as the
> product moves toward GA.

## How this was verified

- **Method:** Live navigation of the Foundry portal "New Foundry" experience using Playwright MCP.
  See the [`foundry-ui-playwright`](../../.github/skills/foundry-ui-playwright/SKILL.md) skill for the
  navigation procedure and re-verification steps.
- **Environment:** a non-production Foundry resource (`Microsoft.CognitiveServices/accounts`, kind
  `AIServices`) in `japaneast`. No environment identifiers are recorded here by design.
- **Last verified:** 2026-06-15.
- **Caveat:** Several of the strongest Foundry controls are in **Preview**, and **Evaluations** was
  RBAC-gated in the test account. Re-confirm before relying on any single cell.

## Legend

**Coverage** (Foundry GUI):
🟢 Direct control · 🟡 Partial / monitoring-only · 🔴 No dedicated GUI control

**Primary owner / Supporting:** planning hypotheses for the relevant control slice, not authoritative
compliance assignments.

**Verdict** (for partial/none):
- **Gap** — belongs to the AI-orchestration layer, but has no dedicated Foundry control today (or Preview-only).
- **Out of scope** — correctly owned by a different layer (app code, identity, model provider, UX).
- **Shared** — split across Foundry and another layer (typically data/supply-chain provenance).
- **Covered** — effectively handled for the observed Foundry GUI slice; not a claim that the whole OWASP
  risk is solved.

## Foundry GUI controls observed (2026-06-15)

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

| # | Risk | Foundry GUI control | Cov | Verdict | Primary owner | Supporting |
|---|------|---------------------|-----|---------|---------------|------------|
| LLM01 | Prompt Injection | Guardrails: Jailbreak + Indirect prompt injections + Spotlighting; enforce via Compliance Policies | 🟢 | Covered | **Foundry** | Defender for AI, APIM |
| LLM02 | Sensitive Information Disclosure | Guardrails: PII; Compliance: Purview DLP/sensitive-data monitoring | 🟢 | Covered | **Purview** + Foundry | Entra, Azure AI Search (RAG trimming), Defender |
| LLM03 | Supply Chain | Operate → Assets registry + Security posture (Defender) recs | 🟡 | Shared | **Other** (GHAS, Azure Policy) + **Defender for Cloud** (vuln) | Azure API Center (leads API/tool/MCP inventory + allow-listing), APIM (runtime), Purview (model/data lineage), Foundry |
| LLM04 | Data and Model Poisoning | Build → Data/Knowledge governance + Purview (indirect) | 🔴 | Shared | **Purview** + Foundry | Azure AI Search (index provenance/RBAC), Other (model provider, Storage immutability) |
| LLM05 | Improper Output Handling | Output-side guardrails reduce bad output, but downstream sanitization is app-side | 🟡 | Out of scope | **Other** (app code / GHAS) | APIM, Foundry |
| LLM06 | Excessive Agency | Guardrails: Task adherence; tool auth scoping | 🟡 | Gap | **Entra** + Foundry | APIM, Azure API Center (curated/approved tool catalog) |
| LLM07 | System Prompt Leakage | No dedicated control (Jailbreak/Spotlighting help indirectly) | 🔴 | Out of scope | **Other** (architecture, Key Vault) | Entra (managed identity ⇒ no secrets in prompt), Foundry, Defender |
| LLM08 | Vector and Embedding Weaknesses | RBAC on Knowledge/Data connections only | 🔴 | Shared | **Azure AI Search + Entra** | Purview (classification/labels), Private Link |
| LLM09 | Misinformation | Evaluations (groundedness/relevance) — RBAC-gated in test env | 🟡 | Covered | **Foundry** | Azure AI Search (retrieval quality/provenance), Other (human review) |
| LLM10 | Unbounded Consumption | Operate → Quota (deployment capacity) + Overview usage monitoring | 🟡 | Gap | **API Management** + Foundry | Defender/Monitor, Entra |

## OWASP Top 10 for Agentic Applications (2026)

| # | Risk | Foundry GUI control | Cov | Verdict | Primary owner | Supporting |
|---|------|---------------------|-----|---------|---------------|------------|
| ASI01 | Agent Goal Hijack | Guardrails: Indirect prompt injections + Jailbreak + Task adherence | 🟢 | Covered | **Foundry** | Defender for AI, Sentinel |
| ASI02 | Tool Misuse & Exploitation | Guardrails Task adherence (tool call) + PII (tool call/response); tool auth | 🟡 | Gap | **API Management** + Foundry | Entra, Defender, Azure API Center (vetted tool/MCP registry + allow-listing) |
| ASI03 | Agent Identity & Privilege Abuse | Build → Tools auth (OAuth Passthrough/Entra) + Operate → Admin RBAC | 🟡 | Out of scope | **Entra** | Sentinel (UEBA), Defender for Identity |
| ASI04 | Agentic Supply Chain Compromise | Assets registry + Security posture (Defender) + connection governance | 🟡 | Shared | **Azure API Center** (MCP/tool registry, allow-listing) + **Defender for Cloud** + Other (GHAS, Azure Policy) | Foundry, APIM |
| ASI05 | Unexpected Code Execution | No user-facing knob (sandboxing is platform-internal) | 🔴 | Out of scope | **Foundry** (sandbox) + Defender | Other (container/network isolation) |
| ASI06 | Memory & Context Poisoning | Indirect prompt injection guardrail (tool-response ingestion); Memory feature has no poisoning control | 🟡 | Gap | **Foundry** | Azure AI Search (retrieved-context provenance/partitioning), Purview, Other |
| ASI07 | Insecure Inter-Agent Communication | No GUI control for A2A channel security | 🔴 | Gap (emerging) | **API Management + Entra** | Other (Private Link, mTLS), Foundry, Azure API Center (A2A/MCP endpoint inventory) |
| ASI08 | Cascading Agent Failures | Monitoring only: Operate → Overview (health/alerts/anomalies) + Quota | 🟡 | Gap | **API Management** + Foundry | Sentinel, Azure Monitor |
| ASI09 | Human-Agent Trust Exploitation | Indirect: content-harm/groundedness reduce deceptive output | 🔴 | Out of scope | **Other** (UX, training, provenance labels) | Foundry, Purview |
| ASI10 | Rogue / Shadow Agents | Assets inventory + Overview agent discovery + Admin + Defender detection | 🟡 | Gap | **Sentinel + Defender for Cloud** | Entra (Agent ID inventory), Foundry, Azure API Center (sanctioned-tool baseline + Dev Proxy shadow detection) |

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
- **Entra (primary/co on ~4):** LLM06, LLM08, ASI03, ASI07 — who/what an agent is and may do. The
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
(runtime traffic/cost) + Purview (data) + Sentinel/Defender (detect & respond). Most Foundry "gaps" (LLM06, LLM10, ASI02/07/08/10) are
**intentional hand-offs** to those layers — *provided* you have actually deployed and wired them.
Foundry's Operate/Compliance tab covers the in-context slice; the rest of the story lives in the
adjacent layers. The Foundry-owned gaps cluster in the **agentic-era** controls (tool agency, memory,
multi-agent comms, consumption/cost, rogue agents), which extend beyond the content-safety controls
Foundry covers most strongly today.

## Per-product deep dives

Detailed, per-product analyses (each scoring the product's role across all 20 risks) live in their own
files so this overview stays readable:

| Product | Deep dive | Status |
|---------|-----------|--------|
| Azure API Center | [api-center.md](./api-center.md) | ✅ Done |
| Microsoft Foundry | _planned_ | ⏳ |
| Microsoft Entra ID (incl. Agent ID) | [entra.md](./entra.md) | ✅ Done |
| Azure AI Search | _planned_ | ⏳ |
| Azure API Management (GenAI Gateway) | _planned_ | ⏳ |
| Microsoft Purview | _planned_ | ⏳ |
| Microsoft Sentinel | _planned_ | ⏳ |
| Microsoft Defender (for Cloud / AI / XDR) | _planned_ | ⏳ |

When adding a new product deep dive, follow the structure of `api-center.md` (what it is/is not →
role across all 20 risks table → focus areas) and reflect any *material* Primary/Supporting roles back
into the master tables above.

## Open questions to iterate

- For each **Out of scope** row, capture the concrete config required in the owning product
  (e.g., the exact Entra Conditional Access / PIM setup for ASI03) so the end-to-end story is auditable.
- Confirm whether the Foundry **gaps** have a REST/Azure Policy equivalent not surfaced in the GUI.
- Re-verify the **Preview** controls (Spotlighting, Indirect prompt injections on tool response, PII,
  Task adherence) at GA and update the coverage cells.
- Validate the official **ASI01–ASI10** wording against the OWASP PDF (press release uses
  "Agent Behavior Hijacking" for ASI01; this table uses "Agent Goal Hijack").
