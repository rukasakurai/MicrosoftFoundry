# Microsoft Entra (incl. Entra Agent ID) — OWASP GenAI Risk Coverage

> _Point-in-time technical capability analysis for planning purposes — not an evaluation, benchmark,
> or criticism of any product. Capabilities change quickly; re-verify before relying on any cell._

Per-product deep dive for the [OWASP GenAI Risk → Microsoft Control Mapping](./README.md). It assesses
where **Microsoft Entra** — including the **Entra Agent ID** capabilities announced at Ignite 2025 —
plays a Primary, Supporting, or no role across the 20 OWASP GenAI risks.

- **Method:** Each risk was analyzed independently (one sub-agent per risk) against verified Entra
  capabilities, then reconciled against the master tables in the [README](./README.md).
- **Sources:** [Security for AI overview](https://learn.microsoft.com/en-us/entra/agent-id/security-for-ai-overview),
  [What are agent identities?](https://learn.microsoft.com/en-us/entra/agent-id/what-are-agent-identities),
  [Conditional Access for agents](https://learn.microsoft.com/en-us/entra/identity/conditional-access/agent-id),
  [What is Microsoft Entra Agent ID](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id),
  [Entra at Ignite 2025](https://learn.microsoft.com/en-us/entra/fundamentals/whats-new-ignite-2025).
- **Hands-on guides in this repo:** [entra-agent-identity.md](../entra-agent-identity.md) (give an agent
  its own identity/token) and [entra-agent-registry.md](../entra-agent-registry.md) (retired Entra
  registration API; Microsoft Agent 365 now provides the unified inventory, while Entra retains identity and
  access-policy enforcement).
- **Last verified:** 2026-07-11.

## What Microsoft Entra is (and is not)

Entra is the **identity control plane**. It decides **who or what an identity is**, **what it may
access**, and **under what conditions** — for human users, workloads, and now **AI agents**. It is *not*
a content-safety, data-classification, runtime-traffic, or vulnerability-scanning plane.

**Capabilities relevant to agentic risk:**
- **Entra Agent ID** — first-class **agent identities** (purpose-built, distinct from human users and
  classic service principals): *blueprints* (templates) + *instances*, parent–child relationships, and
  *security collections*. Three deployment patterns: **assistive** (delegated / on-behalf-of — the agent
  acts within a signed-in user's consented scopes), **autonomous** (its own identity via client
  credentials — not borrowing a human's), and an optional **agent's user account** (1:1 user object for
  mailbox/Teams access).
- **Agent Identity Platform** — agent OAuth flows (autonomous, on-behalf-of, agent-user), token claims,
  agent service principals, **agent-to-agent discovery & authorization over the MCP and A2A protocols**,
  metadata/discoverability, registry roles, inheritable-permissions blueprints, and an SDK.
- **Zero Trust for agents** — **Conditional Access for agents** (agent-identity risk signal; Microsoft
  Managed Policies that block high-risk agents; custom security attributes for scale) and **Identity
  Protection for agents** (detect anomalous/compromised agents and **auto-remediate** them).
- **Entra ID Governance** — least-privilege scoping, **PIM** (time-bound privilege scoping and,
  for eligible human/group assignments, just-in-time elevation), **access packages / entitlement
  management** (approval-gated, time-bound), **access reviews** (recertify/retire access),
  **lifecycle workflows** (retire agents → no orphaned credentials), **managed identities / workload
  identity federation** (secret-less auth), and sign-in/audit logs.

**What it does NOT do (pair accordingly):**
- **No general in-context AI safety** — identity controls don't stop prompt injection, jailbreak,
  hallucination, or memory poisoning at the reasoning layer (→ Foundry guardrails / evaluations).
- **No data classification or redaction** — it gates *access*, not *content* (→ Purview, Foundry PII).
- **No runtime traffic control** — no rate-limits, token quotas, or cost caps (→ API Management, Foundry
  Quota, Azure Cost Management).
- **No vulnerability/provenance scanning** — it proves *who owns/runs* an agent, not whether a tool,
  package, or model is safe (→ Defender for Cloud, GitHub Advanced Security, Purview, API Center).
- **No transport security** — it authenticates the *caller*, not the *channel* (→ mTLS, Private Link).

## Role across all 20 risks

Entra's value concentrates on **identity, least-privilege authorization, and lifecycle** — strongest where
the risk is fundamentally *who an agent is and what it may do*, and weakest where the risk is content,
model, or runtime-behavior centric (where Entra can only **contain blast radius** or **detect/attribute**).

| Risk | Entra role | Lever | Note (who owns the rest) |
|------|------------|-------|---------------------------|
| LLM01 Prompt Injection | Supporting (weak) | Least-privilege + Identity Protection containment/auto-remediation | Foundry guardrails (indirect injection/jailbreak) prevent; Defender/Sentinel detect |
| LLM02 Sensitive Info Disclosure | **Primary (co, access slice)** | OBO/least-privilege scoping limits what sensitive data an agent can reach | Purview classifies/DLP; Foundry PII guardrail redacts |
| LLM03 Supply Chain | Supporting (weak) | Verifiable agent identity + ownership/lifecycle ("who deployed this agent") | Defender/GHAS (vuln), API Center (tool/MCP registry), Purview (model/data lineage) |
| LLM04 Data & Model Poisoning | Supporting (weak) | RBAC/PIM gate *who may write* to data stores & model registries | Purview lineage, Storage immutability, Defender, ML-pipeline integrity detect/prevent |
| LLM05 Improper Output Handling | Supporting (weak) | Least-privilege downstream identity limits damage from unsafe output-triggered actions | App code / secure SDLC / GHAS / Foundry output guardrails own validation/sanitization |
| LLM06 Excessive Agency | **Primary (co)** | Least-privilege scopes, OBO consent, **PIM time-bound scoping** (not eligible-JIT self-activation for service principals), access packages, access reviews | Foundry constrains in-context behavior (task adherence, HITL); APIM throttles action rate |
| LLM07 System Prompt Leakage | Supporting (weak) | **Managed identity / workload-identity federation** ⇒ no secrets need to be embedded in prompts; reduces credential-exposure impact but does not prevent prompt extraction | Foundry/architecture prevent extraction; Key Vault stores secrets |
| LLM08 Vector & Embedding Weaknesses | **Primary (co, access slice)** | RBAC on the vector store (Azure AI Search), **OBO security-trimmed retrieval**, managed identity, access reviews | Purview classifies; vector-DB/app handle inversion/poisoning; Private Link isolates network |
| LLM09 Misinformation | Not applicable | (identity-scoped access to trusted sources only — marginal) | Foundry groundedness/evaluations + content guardrails; human review |
| LLM10 Unbounded Consumption | Supporting (weak) | Auth gate (Entra token requirement blocks anonymous callers; Conditional Access blocks high-risk authenticated callers) + per-caller attribution | APIM GenAI gateway / Foundry Quota / Azure Cost Management enforce limits |
| ASI01 Agent Goal Hijack | Supporting (material) | Least-privilege containment + **Identity Protection** anomaly detection/auto-remediation | Foundry guardrails prevent hijack; Defender/Sentinel detect |
| ASI02 Tool Misuse & Exploitation | Supporting (material) | Entra-protected tool/API scopes bound *what a tool call can reach* (OBO consent, least-privilege app roles, PIM) | APIM validates params/rate-limits; Foundry task adherence; API Center vets the registry |
| ASI03 Agent Identity & Privilege Abuse | **Primary** | Unique non-forgeable agent identity, **PIM time-bound scoping**, access reviews, lifecycle retirement (no orphaned creds), risk-based block | Sentinel/Defender UEBA add detection; Foundry covers in-context behavior only |
| ASI04 Agentic Supply Chain Compromise | Supporting (material) | Verifiable agent/sub-agent identity + **A2A/MCP authenticated authorization** (delegate only to legitimate agents) + ownership/lifecycle | API Center (registry/allow-list), Defender/GHAS (vuln), Purview (provenance) |
| ASI05 Unexpected Code Execution | Supporting (weak) | Least-privilege managed identity for the execution principal limits lateral movement | Foundry sandbox + container/network isolation + Defender + Azure Policy own it |
| ASI06 Memory & Context Poisoning | Supporting (weak) | Identity-scoped write access to the memory store; OBO tokens carry per-user identity, enabling app-level partitioning to reduce cross-user contamination | Foundry memory integrity + content guardrails + Purview validate content |
| ASI07 Insecure Inter-Agent Communication | **Primary (co)** | Verifiable identity + **A2A/MCP token-based authorization**; OBO propagates scoped delegation across the chain | APIM/mTLS/Private Link secure transport & mediation; app validates message schema |
| ASI08 Cascading Agent Failures | Supporting (weak) | Least-privilege blast-radius containment + Identity Protection kill-switch (disable a compromised agent) + audit attribution | APIM circuit breakers/throttling; Foundry orchestration; Monitor/Sentinel detect |
| ASI09 Human-Agent Trust Exploitation | Supporting (weak) | Verifiable agent identity distinguishes agents from humans + audit attribution (anti-impersonation) | UX disclosure, content-provenance labels, user training, app design own it |
| ASI10 Rogue / Shadow Agents | Supporting (material) | Visibility and lifecycle controls for identity-bearing agents, access reviews for orphans, Conditional Access block, Identity Protection auto-remediate | Microsoft Agent 365 owns the unified inventory; Sentinel + Defender hunt workloads with **no** Entra identity; API Center provides the sanctioned-tool baseline |

**Tally:** Primary 5 (LLM02, LLM06, LLM08, ASI03, ASI07 — several co-owned) · Supporting (material) 4
(ASI01, ASI02, ASI04, ASI10) · Supporting (weak) 10 (LLM01, LLM03, LLM04, LLM05, LLM07, LLM10, ASI05, ASI06,
ASI08, ASI09) · Not applicable 1 (LLM09).

## Where Entra leads

Entra is the **clear owner of identity-and-privilege risks** and the identity-lifecycle story:

- **ASI03 — Agent Identity & Privilege Abuse:** the single risk Entra Agent ID was built for. A unique,
  non-forgeable identity per agent + time-bound privilege scoping + access reviews + lifecycle retirement
  directly attack impersonation, confused-deputy, standing over-privilege, and orphaned credentials.
- **LLM02 — Sensitive Information Disclosure:** OBO, least-privilege scopes, and RBAC are primary controls
  for the access slice: they limit what sensitive data an agent can retrieve before content controls apply.
- **LLM06 — Excessive Agency:** least-privilege scopes, on-behalf-of consent, PIM time-bound scoping,
  and approval-gated access packages cap an agent's standing authority at the identity layer — the core OWASP
  mitigation for excessive agency. (Foundry owns the in-context "how it behaves" half.)
- **ASI07 — Insecure Inter-Agent Communication:** Entra's **A2A/MCP authenticated authorization** ensures
  an agent delegates only to *legitimate, authenticated* agents — co-primary with APIM, which secures the
  transport/mediation layer.
- **LLM08 — Vector & Embedding Weaknesses:** RBAC on the vector store plus **on-behalf-of, security-trimmed
  retrieval** is the leading control against cross-user/cross-tenant RAG leakage (co-primary with Purview).

## Where Entra only contains or attributes

For content-, model-, and runtime-centric risks (LLM01, LLM03, LLM04, LLM05, LLM07, LLM09, ASI05, ASI06, ASI08, ASI09),
Entra cannot prevent the failure. Its contribution is **second-order but still worth wiring up**:

- **Blast-radius containment** — least-privilege agent/workload identity means a hijacked agent (LLM01,
  ASI01), executed code (ASI05), or cascading failure (ASI08) can only reach narrowly scoped resources.
- **Kill-switch / auto-remediation** — Identity Protection can disable a compromised agent, breaking a
  goal-hijack (ASI01) or a cascade (ASI08).
- **Attribution & audit** — every agent action is logged under its agent identity, enabling forensics and
  anti-impersonation accountability (ASI09) and feeding Sentinel/Defender.
- **Secret-less auth** — managed identities / workload-identity federation remove the *need* to embed
  credentials in prompts or code, reducing the impact if a prompt leaks (LLM07).

For ASI10, Entra covers the identity-bearing subset; Microsoft Agent 365 provides the unified inventory,
while Sentinel and Defender detect workloads without Entra identities.

**Net:** Entra is a **Primary owner on ~5 risks** and a **material dependency on most of the rest** — but
it must be paired with Foundry (in-context safety), APIM (runtime traffic), Purview (data), and
Sentinel/Defender (detect & respond) for an end-to-end story. Entra answers *who the agent is and what it
may do*; it does not answer *how it behaves, what it processes, or how fast it runs*.
