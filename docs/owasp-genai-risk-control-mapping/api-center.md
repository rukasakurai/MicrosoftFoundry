# Azure API Center — OWASP GenAI Risk Coverage

> _Point-in-time technical capability analysis for planning purposes — not an evaluation, benchmark,
> or criticism of any product. Capabilities change quickly; re-verify before relying on any cell._

Per-product deep dive for the [OWASP GenAI Risk → Microsoft Control Mapping](./README.md). It assesses
where **Azure API Center** plays a Primary, Supporting, or no role across the 20 OWASP GenAI risks.

- **Method:** Each risk was analyzed independently against verified API Center capabilities.
- **Sources:** [API Center overview](https://learn.microsoft.com/en-us/azure/api-center/overview),
  [register/discover MCP servers](https://learn.microsoft.com/en-us/azure/api-center/register-discover-mcp-server),
  [linting & analysis](https://learn.microsoft.com/en-us/azure/api-center/enable-api-analysis-linting).
- **Last verified:** 2026-06-15.

## What Azure API Center is (and is not)

[Azure API Center](https://learn.microsoft.com/en-us/azure/api-center/overview) is a **design-time**
API governance and discovery service (distinct from API Management, which is the **runtime** gateway).

**Capabilities:**
- Org-wide **inventory** of all APIs/tools (managed, unmanaged, under-development) with versions,
  definitions, deployments, and environments.
- **MCP server registry** (remote/local) that integrates with Microsoft Foundry tool catalogs and
  private tool catalogs.
- **Governance via metadata** (approval status, owner, compliance, data classification, lifecycle) →
  enables allow-listing of vetted APIs/tools/MCP servers.
- **Spectral linting** + breaking-change detection (shift-left in VS Code).
- **Shadow API detection** via Dev Proxy (design/test-time).
- Discovery via API Center portal + VS Code extension.

**What it does NOT do (pair accordingly):**
- **No runtime enforcement** — it won't block an agent from calling an unregistered endpoint
  (→ API Management gateway + network policy + Azure Policy to *require* registration).
- **No vulnerability/CVE scanning** (→ Defender for Cloud, GitHub Advanced Security/Dependabot).
- **No model or training-data provenance** — it catalogs APIs, not model weights, LoRA adapters, or
  datasets (→ Purview lineage, model-provider attestation).
- **No identity issuance/enforcement** — it documents auth requirements as metadata only (→ Entra).

## Role across all 20 risks

Because API Center is **design-time governance** (not a runtime enforcement point), it is **Primary
only for the tool/MCP registry slice** (ASI04), **Supporting** where inventory / allow-listing /
shadow-detection materially help, and **Not applicable** for model-, data-, prompt-, identity-, or
runtime-centric risks.

| Risk | API Center role | Lever | Note (who owns enforcement) |
|------|-----------------|-------|------------------------------|
| LLM01 Prompt Injection | Supporting (weak) | Approved tool/MCP catalog | Reduces untrusted-tool surface; Foundry guardrails enforce |
| LLM02 Sensitive Info Disclosure | Supporting (weak) | Data-class metadata, allow-list sensitive-data APIs | Purview/Foundry enforce |
| LLM03 Supply Chain | Supporting (leads tool/API slice) | Inventory, MCP registry, allow-list, shadow detection, linting | Whole-risk primary = GHAS/Azure Policy/Defender (vuln), Purview (model/data) |
| LLM04 Data & Model Poisoning | Not applicable | — | Models/data not cataloged (Purview/Foundry) |
| LLM05 Improper Output Handling | Not applicable | — | Linting = API-contract quality, not runtime output handling (app code) |
| LLM06 Excessive Agency | Supporting | Curated/approved tool catalog limits the agent's toolset | Entra/Foundry enforce least-privilege/HITL |
| LLM07 System Prompt Leakage | Not applicable | — | No role in prompt confidentiality (architecture/Key Vault) |
| LLM08 Vector & Embedding Weaknesses | Supporting (weak) | Govern/discover the retrieval API/MCP endpoint | Vector-store RBAC/Purview/Private Link own the core |
| LLM09 Misinformation | Supporting (weak) | Govern catalog of trusted grounding-source APIs | Foundry groundedness/evaluations enforce |
| LLM10 Unbounded Consumption | Not applicable | — | Metadata documents limits; APIM/Quota enforce |
| ASI01 Agent Goal Hijack | Supporting (weak) | Tool allow-list + shadow detection | Foundry guardrails (indirect injection/task adherence) enforce |
| ASI02 Tool Misuse & Exploitation | Supporting (material) | Vetted tool/MCP registry + allow-listing + shadow detection | APIM/Foundry constrain runtime tool calls |
| ASI03 Agent Identity & Privilege Abuse | Not applicable | — | Documents auth as metadata only; Entra enforces identity |
| ASI04 Agentic Supply Chain Compromise | **Primary (co, registry slice)** | MCP/tool registry, allow-list, linting, shadow detection | Not vuln/runtime — Defender/GHAS (vuln), Azure Policy/APIM (runtime) |
| ASI05 Unexpected Code Execution | Not applicable | — | No sandbox; Foundry/Defender own |
| ASI06 Memory & Context Poisoning | Supporting (weak) | Approve/register context-source APIs/MCP servers | Foundry memory integrity, Purview |
| ASI07 Insecure Inter-Agent Communication | Supporting | Inventory A2A/MCP endpoints + declared auth/transport | APIM/Entra/mTLS secure the channel |
| ASI08 Cascading Agent Failures | Supporting (weak) | Design-time dependency / blast-radius map | APIM/Foundry contain; Sentinel/Monitor detect |
| ASI09 Human-Agent Trust Exploitation | Not applicable | — | Human/UX factor; no API Center role |
| ASI10 Rogue / Shadow Agents | Supporting (material) | Sanctioned-tool baseline + Dev Proxy shadow detection | Sentinel/Defender do runtime hunting/response |

**Tally:** Primary 1 · Supporting 12 · Not applicable 7. API Center's value concentrates on the
**tool/MCP supply-chain and inventory** dimension (ASI04 primary; ASI02, ASI10, LLM06, LLM03 material
support). Everywhere else it is weak-supporting *visibility* or has no role — consistent with it being
a design-time catalog, not an enforcement plane.

## Supply-chain focus (LLM03 / ASI04)

API Center's strongest fit is the **API / tool / MCP-server dependency** dimension of supply-chain risk.

**What it covers:** org-wide inventory of APIs/tools/MCP servers (eliminates shadow/unknown
dependencies); allow-listing & governance via custom metadata (approval, owner, license, data class),
lifecycle, and versioning; design-time conformance via Spectral linting; GitOps/CI-CD registration for
an auditable record of what enters the estate.

**What it does NOT cover:** runtime blocking of unregistered endpoints (→ APIM + network + Azure
Policy); CVE/vuln scanning (→ Defender for Cloud, GHAS/Dependabot); model/training-data provenance
(→ Purview lineage, model-provider attestation).

It overlaps Foundry's **Operate → Assets** (Foundry-scoped inventory); API Center is the broader
**cross-platform, org-wide** catalog. Net: API Center is the natural owner of the registry/allow-list
slice, but the coverage stays partial because model/data provenance, vuln-scanning, and runtime
enforcement remain with other layers.
