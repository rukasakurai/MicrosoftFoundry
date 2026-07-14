# Foundry Guide web app

This optional deployment adds an authenticated desktop/mobile browser client for
the Foundry Guide `prompt agent`.

## Selected architecture

One Linux Azure App Service web app serves the TypeScript SPA and ASP.NET Core API:

```text
Browser
  → Microsoft Entra access token
  → App Service SPA/API
  → managed identity
  → Foundry Guide stable endpoint
```

Authentication uses the Microsoft Entra tenant associated with the Azure
subscription that contains the Foundry resources. The same tenant therefore owns
the user identities, app registration, deployment identity, and Azure resources.

The API emits the application-owned `foundry_guide.feedback` custom event and
stores only short-lived feedback correlation records. It doesn't store prompts,
responses, user identifiers, secrets, or Azure deployment identifiers.

## Options considered

Status is current as of 2026-07-14.

| Option | Feasibility | Decision |
| --- | --- | --- |
| Foundry `prompt agent` + static frontend | **Technically feasible.** The live endpoint accepts browser CORS and an undocumented `OpenIdConnect` authorization scheme. A temporary principal with no Foundry RBAC reached request validation using a non-Foundry token audience. | Not selected because Foundry doesn't host the SPA and a `prompt agent` can't emit trusted application feedback. The custom OIDC surface isn't documented or represented by current SDKs. |
| Foundry `hosted agent` + static frontend | A `hosted agent` could own chat and server-side feedback through Responses + Invocations. | Future option. Custom OIDC remains undocumented, the `Azure.AI.AgentServer.*` packages have no stable release, source-code deployment is Preview, and hosted container compute replaces the simpler managed `prompt agent`. |
| Azure Static Web Apps + Function | Documented cross-tenant authentication, same-origin API routing, managed identity, and scale-to-zero API compute. | Not selected because it creates two application deployment surfaces, requires Static Web Apps Standard for the linked backend/custom auth, and retains Function host storage plus the Static Web Apps deployment-token path. |
| Azure App Service | One origin and deployable, mature authentication, managed identity, built-in .NET runtime, and no container registry. | **Selected.** The fixed plan charge buys the simplest deployment and avoids cold starts. |
| Azure Container Apps | One origin and deployable, managed identity, consumption billing, and scale-to-zero. Microsoft’s current `microsoft-foundry/foundry-agent-webapp` sample uses this shape. | Not selected because it adds ACR, image builds, base-image patching, and a two-stage deployment. Reconsider if scale-to-zero savings become more important than operational simplicity. |
| Azure Front Door | Feasible as a CDN, WAF, and routing layer. | Not selected because it doesn't host the app, authenticate users, or acquire Foundry tokens. Add it only for a demonstrated WAF, origin-lockdown, or multi-origin requirement. |

At Japan East public list prices on 2026-07-14, Linux App Service B1 is
US$0.019/hour (about US$13.87 for 730 hours). ACR Basic is US$0.1666/day
(about US$5.07 for 30.4 days), before Container Apps usage above its monthly free
grant. The approximate US$9/month difference isn't large enough for this application
to justify the registry and container lifecycle. These are estimates, not actual
subscription spend.

References: [App Service plans](https://learn.microsoft.com/azure/app-service/overview-hosting-plans),
[Container Apps billing](https://learn.microsoft.com/azure/container-apps/billing),
[Static Web Apps APIs](https://learn.microsoft.com/azure/static-web-apps/apis-overview),
[Azure Front Door](https://learn.microsoft.com/azure/frontdoor/front-door-overview),
and Microsoft’s current
[`foundry-agent-webapp`](https://github.com/microsoft-foundry/foundry-agent-webapp)
sample.

## Access boundary

Create one single-tenant app registration in the Microsoft Entra tenant associated
with the Azure resource subscription:

1. Expose the API scope `access_as_user`.
2. Configure access tokens as version 2.
3. Pre-authorize the SPA client (the same client ID) for that scope.
4. Add the deployed app URL as a **Single-page application** redirect URI.
5. Leave **Assignment required?** set to **No** so any user in the tenant can sign in.

Applications registered in a tenant are available to its users by default. The API
still validates the tenant-specific issuer, v2 client-ID audience, and
`access_as_user` scope, so tokens issued by other tenants are rejected.
Cross-tenant access is out of scope.

Use the repository owner's normal member account in this tenant for one-time setup,
manual deployment, and interactive testing. Its credentials are never stored in
GitHub. The web app uses its system-assigned managed identity and receives only:

- Foundry Agent Consumer on the Foundry project;
- Storage Table Data Contributor on the feedback-correlation account.

The agent endpoint uses header-based isolation. The API derives an opaque per-user
key from the authenticated token and creates a separate key for each chat. It
doesn't log or persist the user identifier.

## GitHub Environment

The deployment workflow targets the `foundry-guide` GitHub Environment. The
environment requires owner approval and permits deployments only from `main`.

Configure:

| Type | Name |
| --- | --- |
| Variable | `AZURE_CLIENT_ID` |
| Variable | `AZURE_ENV_NAME` |
| Variable | `AZURE_LOCATION` |
| Variable | `AZURE_PRINCIPAL_ID` |
| Variable | `FOUNDRY_GUIDE_WEB_ENABLED` |
| Variable | `FOUNDRY_GUIDE_WEB_AUTH_CLIENT_ID` |
| Secret | `AZURE_TENANT_ID` |
| Secret | `AZURE_SUBSCRIPTION_ID` |

The Azure federated credential subject must target:

```text
repo:<owner>/<repository>:environment:foundry-guide
```

The workflow uses OIDC for Azure access, builds one ZIP artifact, and deploys it
through Azure RBAC. The federated workload identity is the routine deployment
identity; it stores no cloud or publishing credential in GitHub.

## Deploy

Set `FOUNDRY_GUIDE_WEB_ENABLED=true`, configure the GitHub Environment, then run
**Deploy Foundry Guide Web**.

The first run provisions the persistent environment and outputs the App Service
URL privately. Add that URL to the app registration:

```text
<FOUNDRY_GUIDE_WEB_APP_URL>
```

No redeployment is needed after registering the redirect URI. Do not publish the
app URL or tenant/application identifiers.

## Verification

Use Playwright MCP to verify sign-in, chat, feedback, and desktop/mobile layouts.
Select and run regression coverage through
`.github/skills/e2e-foundry-baseline/`, including Flow 16 and every affected flow.

## Hosted-agent revisit

Reconsider replacing the App Service backend with a `hosted agent` when all of
these are true:

- custom OIDC endpoint authorization is documented and supported by an SDK;
- the required AgentServer protocol packages have stable releases;
- the deployment path used here is GA;
- browser invocation and trusted feedback are covered by supported contracts.

The static frontend would still need a web host unless Foundry adds a documented
general-purpose static-content surface.
