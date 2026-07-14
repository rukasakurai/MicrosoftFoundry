---
name: foundry-ui-playwright
description: Use Playwright MCP to navigate, verify, and capture the Microsoft Foundry portal (ai.azure.com) UI, and to check learn.microsoft.com Foundry documentation against the live portal before relying on it. Includes how to set up the Playwright MCP server for both GitHub Copilot CLI and Copilot in VS Code. Use when asked to set up Playwright MCP, confirm that a documented Foundry UI element/pane actually exists, walk the Foundry portal, or compare docs with reality.
---

# Navigating the Microsoft Foundry UI with Playwright MCP

## When to Use

- You need to confirm whether a UI element described in learn.microsoft.com (for example a pane like **Operate → Assets**) actually exists in a real Foundry deployment.
- You prefer code/IaC/REST/MCP but need to understand or screenshot how something works in the Foundry **GUI**.
- A learn.microsoft.com Foundry page may be ahead of or behind the live portal, and you want to verify before trusting it.

This skill assumes the **Microsoft Foundry resource** architecture (`Microsoft.CognitiveServices/accounts`, kind `AIServices`) provisioned by this repo. For the ARM provider distinctions, see the `microsoft-foundry-resources` skill.

## Foundry portal navigation map

Portal root: `https://ai.azure.com`.

### The "New Foundry" experience toggle (most important gotcha)

The portal has two experiences, switched by a **toggle in the top toolbar** (aria-label: *"Toggle to switch to the new Azure AI Foundry experience"*, labeled **New Foundry**).

- **Control Plane** features — the **Operate** menu and its panes — **only appear when the new experience is ON.** In the classic experience there is no Operate/Assets, so a "the doc is wrong, that pane doesn't exist" conclusion is usually a false negative caused by the toggle being off.
- Always check and, if needed, enable the toggle **before** concluding a documented pane is missing.
- URL signal: the new experience uses a `/nextgen/...` path; the classic one uses `/foundryProject/...` or `/resource/...`.

### Operate (Control Plane) panes

> **"Control Plane" is a docs-only term — the GUI calls it "Operate".** The learn.microsoft.com articles brand this surface *Microsoft Foundry Control Plane*, but the live portal never uses that label for the feature: the menu is **Operate** and the panes are Overview/Assets/Compliance/Quota/Admin. The string "control plane" appears only once in the UI, lowercase, inside an *Ask AI* suggested-prompt chip on the Overview pane. So when a doc says "Control Plane", look for **Operate** in the portal. (Verified live 2026-06-15.)

When the new experience is on, the left nav shows **Operate**, containing (each pane
lands on a default sub-tab; **"demo/verify Operate" means covering every sub-tab, not
just the landing view**):

| Pane | Path suffix | Sub-tabs (landing first) |
| --- | --- | --- |
| Overview | `/operate/overview` | — (fleet health: alerts, running agents, cost, success rate, token usage, run-volume chart) |
| Assets | `/operate/assets` | **Agents** / **Models** / **Tools** (subscription-wide); **Register asset** button |
| Compliance | `/operate/compliance` | **Policies** / **Guardrails** / **Security posture** (Microsoft Defender for Cloud) / **Data security and governance** (Microsoft Purview) |
| Quota | `/operate/quota` | **Token per minute** / **Provisioned throughput unit** / **Managed compute** |
| Admin | `/operate/manage` | **All projects** (parent resource + region) / **AI Gateway** (preview) |

**Reach a Compliance/Quota sub-tab by clicking its tab** from the pane, not by guessing a
URL slug. The slugs are not uniform — e.g. Compliance is `/policies`, `/guardrails`,
`/security-posture`, and `/dataSecurityGovernance` (camelCase). Clicking the tab lands the
correct slug and renders; a hand-built kebab guess can load an empty shell. (Verified live
2026-07-07.)

Assets aggregates **subscription-wide across all projects** (columns like Status,
Version, Error rate, Estimated cost, Token usage on the Agents sub-tab; endpoint on
the Tools sub-tab), which makes it the place to confirm a fleet-wide view of what a
provisioning change produced. (Verified live 2026-07-07: a Bicep-provisioned Foundry IQ
`RemoteTool` connection appears under **Assets → Tools** with its knowledge-base MCP
endpoint, and its agent under **Assets → Agents**.)

### Build (authoring) panes

The **Build** menu is where you author and test. Its panes (verified live 2026-07-07):

| Pane | Path suffix | Notes |
| --- | --- | --- |
| Agents | `/build/agents` | Agent list; open one for the **Playground** (chat + Tools/Knowledge bindings), Details, Traces |
| Models | `/build/models` | Model deployments |
| Tools | `/build/tools` | Connected tools (MCP, etc.) |
| Knowledge | `/build/knowledge` | Labeled **"Knowledge (Foundry IQ)"**; tabs **Knowledge bases / Indexes** |
| Guardrails | `/build/guardrails` | |
| Memory | `/build/memory` | |
| Data | `/build/data` | |

**Navigate Build sub-panes by clicking the left-nav link from `/build`** (or from any
Build pane). The click-through navigation is reliable; the project-root deep link in the
next section lands you correctly, and from there the in-app links do the rest.

**Foundry IQ in the portal (verified 2026-07-07).** An agent's Playground shows its bound
knowledge base under **Knowledge** (e.g. `kb-foundry-iq`), and a grounded query renders
inline citations with the trace `mcp_list_tools → knowledge-base → message` — the
signature of the `knowledge_base_retrieve` MCP tool. To *browse* a knowledge base under
**Build → Knowledge**, select a Foundry IQ (Azure AI Search) resource and choose **Connect**;
the portal creates its own browse connection for that pane (default auth **API Key**),
which is separate from any connection your IaC provisions for an agent's runtime use.

### Building a deep link from azd outputs

You can jump straight to a project workspace instead of clicking through. Get the values with `azd env get-values`, then construct:

```
https://ai.azure.com/resource/overview?tid=<AZURE_TENANT_ID>&wsid=<ARM resource id of the project>
```

The project ARM id (`wsid`) has the form:
`/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project>`

The portal redirects this to the appropriate `/foundryProject/...` or `/nextgen/...` URL once loaded.

## Playwright MCP tips for this context

- **Browser authentication is profile-specific.** If the portal opens signed out, complete its normal interactive flow; see [references/setup.md](references/setup.md) for profile behavior. Then use `browser_tabs` to confirm that the URL contains a `?tid=...` tenant parameter.
- **Prefer `browser_snapshot` (accessibility tree) over screenshots** for finding and clicking elements. Use `browser_take_screenshot` only for visual confirmation/evidence.
- **Use `browser_find` before dumping a large snapshot** when locating a known label.
- **The browser stays open across tool calls** until `browser_close`. Close it when done to free the session.
- **Use this browser session for navigation and inspection.** Provision Azure resource changes through IaC/CLI, then use the portal to confirm they appear.
- **Docs vs reality flow:** read the doc text first via `web_fetch` on the docs API (`https://learn.microsoft.com/api/article/body?pathname=/en/azure/foundry/...`) for clean markdown; then use Playwright to confirm the exact live labels/panes. Note any drift (label renames, preview gating, toggle requirements) with the date, since the portal changes often.
- **Inspecting what a pane actually loads:** the `/nextgen` portal calls a private internal BFF (`ai.azure.com/nextgen/api/...Resolver`, no `api-version`), **not** public ARM (`management.azure.com`). When you need to confirm a feature is real from its network traffic, or to understand the docs' "available through the Foundry portal only" wording, see **[references/portal-backend-api.md](references/portal-backend-api.md)**.
- **Azure Pricing Calculator:** when navigating the public calculator, keep the session signed out and use the repo-specific notes in **[references/pricing-calculator.md](references/pricing-calculator.md)**.

## Setting up the Playwright MCP server

If the Playwright MCP server is not yet configured (or its tools vanished after a config change), see **[references/setup.md](references/setup.md)**. It covers first-time install, the GitHub Copilot CLI vs GitHub Copilot in VS Code config differences, keeping artifacts out of the repo (`PLAYWRIGHT_MCP_OUTPUT_DIR`), headless-Linux `DISPLAY` settings, and browser launch failures.
