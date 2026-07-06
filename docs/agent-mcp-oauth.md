# Connecting a Foundry Agent to an Authenticated Remote MCP Server

This guide shows how a Microsoft Foundry agent connects to an **OAuth-authenticated
remote [MCP](https://modelcontextprotocol.io/) server**, using the
[GitHub MCP server](https://github.com/github/github-mcp-server)
(`https://api.githubcopilot.com/mcp/`) as a worked example. It covers the two
connection shapes and where authentication is configured in each:

- **Direct**: `Agent → MCP server`
- **Toolbox**: `Agent → Foundry Toolbox → MCP server`

It complements [agent-creation.md](./agent-creation.md), which covers creating a
plain agent. For the authoritative reference, see
[Connect to MCP server endpoints](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol)
and [Set up MCP server authentication](https://learn.microsoft.com/azure/foundry/agents/how-to/mcp-authentication).

## Where credentials live

An agent never carries MCP credentials inline. Instead, the credentials are
stored in a **project connection**, and the agent's `mcp` tool references that
connection by name via `project_connection_id`. The connection is
**project-scoped**: the agent must run in the same Foundry project as the
connection.

Foundry supports several auth methods for a connection (key-based, Microsoft
Entra, and **OAuth identity passthrough**). This guide uses OAuth identity
passthrough, because it preserves each user's own identity — the pattern that
matters for production systems where per-user permissions and audit trails are
required.

## Direct path: Agent → MCP server

### 1. Create the project connection (once)

Create an OAuth connection to the MCP server. For a third-party server you must
use **custom OAuth** with your own OAuth app (see the gotcha about Microsoft
tokens below). For the GitHub MCP server, register a
[GitHub OAuth App](https://github.com/settings/developers) and configure the
connection with:

| Field | Value |
| --- | --- |
| Remote MCP Server endpoint | `https://api.githubcopilot.com/mcp/` |
| Authentication | OAuth Identity Passthrough |
| Client ID / secret | from your GitHub OAuth App |
| Auth URL | `https://github.com/login/oauth/authorize` |
| Token URL | `https://github.com/login/oauth/access_token` |
| Refresh URL | `https://github.com/login/oauth/access_token` |
| Scopes | e.g. `read:user` (space-separated if multiple) |

After you create the connection, Foundry gives you a **Redirect URL**. Add it to
the GitHub OAuth App's *Authorization callback URL* to close the loop.

The Foundry portal creates the connection for you and keeps the client secret on
its side. You can inspect (but not read the secret of) the connection with:

```bash
az cognitiveservices account connection show \
  --connection-name github -n <account> -g <resource-group>
# -> authType: OAuth2, category: RemoteTool, target: https://api.githubcopilot.com/mcp/
```

### 2. Create the agent and run it

Use [scripts/create-mcp-agent.sh](../scripts/create-mcp-agent.sh):

```bash
eval $(azd env get-values) && ./scripts/create-mcp-agent.sh \
  --connection github \
  --prompt "What is my GitHub username? Use the GitHub MCP tools."
```

The agent's tool is wired to the connection:

```json
{
  "type": "mcp",
  "server_label": "github",
  "server_url": "https://api.githubcopilot.com/mcp/",
  "require_approval": "always",
  "project_connection_id": "github"
}
```

### 3. Consent and approval

On first use, the run returns an `oauth_consent_request` with a `consent_link`.
The user opens it, signs in to the MCP server, and consents. Consent is
remembered **per user, per tool, per project** — it is a one-time step.

With `require_approval: always`, each tool call also returns an
`mcp_approval_request`. Continue by submitting an `mcp_approval_response` with
`previous_response_id`:

```json
{
  "previous_response_id": "<id from the prior response>",
  "input": [{
    "type": "mcp_approval_response",
    "approve": true,
    "approval_request_id": "<mcp_approval_request id>"
  }],
  "agent_reference": { "name": "mcp-oauth-agent", "type": "agent_reference" }
}
```

The sequence is: the first run returns `oauth_consent_request` (until the user
consents once), then `mcp_approval_request` per call, and finally an `mcp_call`
with the tool result plus the assistant's `message`. For example, asking
"What is my GitHub username?" drives a `get_me` call whose output includes the
user's GitHub `login`.

### Evidence-safe validation: assistant text is not proof

For any tool-backed agent, the assistant's `message` is **not** proof that the tool
actually ran — the model can produce a plausible answer with no verifiable tool
invocation. Treat a run as verified only when the raw output items contain an actual
`mcp_call` (with output), not just prose.

`scripts/classify-agent-run.sh` inspects a Responses API response and classifies the
run:

- **pass** — an `mcp_call` returned output (a verifiable tool invocation).
- **fail** — an `mcp_call` returned an error (auth / consent / config / runtime).
- **invalid** — assistant text and/or a pending consent/approval request, but **no**
  verifiable tool invocation (the false-confidence case).

```bash
# Classify a saved response, or pipe one straight from a run:
./scripts/classify-agent-run.sh --file response.json
# exit code: 0 = pass, 1 = fail, 2 = invalid  (CI-friendly)
```

The verdict is secret-free (it never prints tokens, consent links, or
tenant-specific identifiers). `scripts/create-mcp-agent.sh` runs this classifier
automatically after a run.

For authoritative, server-side evidence beyond a single run, use the Foundry portal
**Traces** tab / Application Insights (provisioned by `infra/` when
`enableObservability` is on) and the built-in **Tool Call Success / Accuracy**
evaluators. The classifier is the lightweight, CI-friendly complement.

### Verify in the Foundry portal

You can also exercise the same agent interactively:

1. Open the project in the [Foundry portal](https://ai.azure.com), making sure the
   directory selector (top right) is the tenant that owns the project.
2. Go to **Build → Agents** and open the agent created above. Its config shows the
   MCP tool wired to the `github` connection.
3. Open the agent's **playground / Try** view and send:
   *"What is my GitHub username? Use the GitHub MCP tools."*
4. On first use you may be prompted to sign in and consent (OAuth passthrough);
   with `require_approval: always` you then **Approve** each tool call in the UI.
5. The agent returns the result from the live `get_me` tool call.

Consent is remembered per user, per tool, per project, so subsequent runs skip
the sign-in step. To inspect the stored connection, see the project's
**Connections** (or **Connected resources**) settings.

## Toolbox path: Agent → Toolbox → MCP server

> The direct path above is verified end-to-end in this repo. Toolbox **consumption**
> is also verified (see below); Toolbox **creation** and the portal agent-build
> surface are currently a preview experience.

A [Foundry Toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox)
bundles several tools (including MCP servers) behind a single MCP-compatible
endpoint. The agent points its `mcp` tool at the **Toolbox** endpoint instead of
the MCP server, using the same `server_url` / `server_label` shape.

**How the indirection changes auth:** with a Toolbox, the agent authenticates to
the *Toolbox* endpoint with **Microsoft Entra** credentials
(`DefaultAzureCredential`), and the Toolbox centrally manages the downstream MCP
credentials — injection, token refresh, and policy — for every tool in the
bundle. Individual agents no longer carry per-MCP credentials, and you can add or
reconfigure tools without changing agent code. See
[Toolbox prerequisites](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox#prerequisites)
for the Entra configuration.

| | Direct | Toolbox |
| --- | --- | --- |
| Agent authenticates to | the MCP server (via the connection) | the Toolbox (Entra) |
| MCP credentials stored in | the project connection | the Toolbox |
| Token refresh / policy | per connection | centralized in the Toolbox |
| Change tools without touching agents | no | yes |

### When to use the Toolbox vs. connect directly

Prefer the direct `Agent → MCP` connection for a single MCP server and a few
agents; the Toolbox's indirection adds an auth hop for little benefit at that
scale. Reach for a Toolbox when its centralization pays off — see
[Foundry Toolbox overview](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox).
It is also currently a portal/preview experience.

### Consuming a Toolbox (verified 2026-07-03)

An agent (or any MCP client) consumes a Toolbox through its MCP endpoint:

- Consumer (always serves the default version): `{project_endpoint}/toolboxes/{name}/mcp?api-version=v1`
- Developer (a specific version): `{project_endpoint}/toolboxes/{name}/versions/{version}/mcp?api-version=v1`

**Consumption auth model — the key contrast with a direct connection:** the caller
authenticates to the *Toolbox* with **its own Microsoft Entra token**
(`DefaultAzureCredential`, scope `https://ai.azure.com/.default`) — it does **not**
pass any per-tool credential. Every request must also carry the preview header
`Foundry-Features: Toolboxes=V1Preview`. The Toolbox injects each downstream tool's
credentials itself.

**The pitfall the gateway enforces:** authenticating to the Toolbox the way you'd
authenticate to a direct MCP server — an API key / subscription key instead of an
Entra bearer token — fails at the gateway with
`401 "Access denied due to invalid subscription key or wrong API key"`.

To exercise this cleanly, bundle an **auth-free MCP** (for example the
[Microsoft Learn MCP](https://learn.microsoft.com/api/mcp)). Holding downstream
tool auth at "none" isolates the *Toolbox-consumption* auth as the only variable,
so a failure can't be ambiguous. Tools then surface namespaced as
`{server_label}___{tool}` (for example `learn___microsoft_docs_search`).

**Portal vs. code (verified 2026-07-03):** the new-experience portal manages
Toolboxes under **Build → Tools → Toolboxes** (create, list, and an
*Endpoint + samples* pane titled *"Call this toolbox in code"*). In the agent
builder, the **Add tool → Select a tool** picker (Configured / Catalog / Custom)
offers direct **MCP**, OpenAPI, A2A, and catalog tools — but **no first-class
option to consume a Toolbox**. So an agent consumes a Toolbox via **code/SDK**,
not by adding it in the portal Playground. For the SDK/REST consumption samples,
see [Create, test, and deploy a toolbox](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox)
rather than reproducing them here.

**RBAC:** building agents and consuming tools/toolboxes requires the data-plane
**Foundry User** role on the project — control-plane roles such as subscription
Owner or Contributor do not confer it. This repo's Bicep grants the deploying
principal that role during `azd up` (see `infra/main.bicep`), so the baseline is
usable without a manual step. For the full role matrix, see
[Toolbox prerequisites](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/toolbox#prerequisites).

## What keeps the connection valid over time

OAuth identity passthrough relies on the stored user token staying valid. **Token
lifetime is provider-dependent, and it is the most common place the connection
"breaks over time":**

- **Short-lived tokens (e.g. Microsoft Entra and many SaaS OAuth providers):**
  access tokens expire (often within hours to a day). Include the `offline_access`
  scope and a working **refresh URL** so Foundry can silently refresh. If
  `offline_access` is missing or the refresh URL is wrong, the connection works
  initially and then fails once the first token expires — the classic "it broke
  the next day" symptom.
- **Non-expiring tokens (e.g. GitHub OAuth Apps):** user tokens do **not** expire
  by default (GitHub offers no `offline_access` scope), so the connection stays
  valid until the user revokes the app or the OAuth app is deleted. This is why
  the GitHub example here does **not** reproduce a daily-expiry failure — the
  breakage class simply doesn't apply unless you opt into *expiring user tokens*
  on the app (in which case you must configure the refresh URL). A **GitHub App** —
  GitHub's recommended app type — issues expiring user tokens by default; with
  `offline_access` and the refresh URL configured, the direct path was verified
  (2026-07-03) to refresh them silently past expiry, with no re-consent.

The practical takeaway: for any new MCP server, check its token lifetime and
whether it issues refresh tokens, then configure `offline_access` + refresh URL
accordingly. Don't assume a working first call means the connection is durable.
**Not all providers behave the same:** Foundry will *use* a refresh token when one
exists, but each provider decides whether it *issues* one, and its own rotation,
expiry, and re-consent policies still apply — so a result verified for one provider
does not guarantee the same for another.

## Gotchas

- **"Cannot pass Microsoft token to untrusted MCP endpoint."** Foundry blocks
  Microsoft-audience tokens from being sent to third-party MCP servers. Use
  **custom OAuth** with your own app registration / audience for non-Microsoft
  servers.
- **Redirect URL registration.** The connection's Redirect URL (e.g.
  `https://global.consent.azure-apim.net/redirect/<id>`) must be added to your
  OAuth app's *Authorization callback URL* **after** the connection is created, or
  consent fails. A stale or truncated consent link surfaces as a generic
  `Server Error in '/' Application` from the consent broker — regenerate it by
  re-running the agent.
- **Tenant match & role.** For OAuth passthrough, the consuming user's Entra
  tenant must match the project's tenant, and the user needs at least the
  **Foundry Agent Consumer** role on the project.
- **GitHub token endpoint content type.** `https://github.com/login/oauth/access_token`
  returns `text/plain` unless the caller sends `Accept: application/json` — a
  common cause of OAuth integration failures with GitHub.
- **API surfaces differ.** Agents use `.../agents/{name}/versions?api-version=v1`;
  runs use `.../openai/v1/responses` (path-versioned, no `?api-version=`).
- **.NET preview SDK gap.** As of `Azure.AI.Projects.OpenAI` 1.0.0-beta.3, the
  `McpTool` type does not expose `project_connection_id`, so the OAuth-passthrough
  pattern is expressed most directly via REST (as in the script above).

## Production migration path

This reference uses a personal `github.com` OAuth App so it is reproducible by
anyone. In an enterprise/production setting, expect additional friction:

- **EMU (Enterprise Managed Users):** third-party OAuth Apps are governed by
  enterprise policy and typically require admin approval before they can be used.
- **GitHub Enterprise with data residency (`*.ghe.com`):** the MCP endpoint is
  **not** `api.githubcopilot.com`; use your tenant's data-residency host, and the
  OAuth authorization server changes accordingly.
- Prefer least-privilege scopes, rotate credentials, and audit tool calls.
