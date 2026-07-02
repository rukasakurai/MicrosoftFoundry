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
| Authentication | OAuth Identity Passthrough → Custom OAuth |
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

> The direct path above is verified end-to-end in this repo. The Toolbox path
> below follows the official Foundry documentation; Toolbox creation is currently
> a portal/preview experience.

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
  on the app (in which case you must configure the refresh URL).

The practical takeaway: for any new MCP server, check its token lifetime and
whether it issues refresh tokens, then configure `offline_access` + refresh URL
accordingly. Don't assume a working first call means the connection is durable.

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
