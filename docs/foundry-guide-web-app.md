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
keeps short-lived feedback correlation records in bounded process memory. It
doesn't store prompts, responses, user identifiers, secrets, or Azure deployment
identifiers.

## Options considered

Status is current as of 2026-07-15.

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
GitHub. The web app uses its system-assigned managed identity and receives only
Foundry Agent Consumer on the Foundry project.

The agent endpoint uses header-based isolation. The API derives an opaque per-user
key from the authenticated token and creates a separate key for each chat. It
doesn't log or persist the user identifier.

## GitHub Environment

The deployment workflow targets the `foundry-guide` GitHub Environment. The
environment requires owner approval and permits deployments only from `main`.
Infrastructure provisioning remains a manual owner operation; routine GitHub
deployments can update only the existing App Service.

Configure:

| Type | Name |
| --- | --- |
| Variable | `AZURE_CLIENT_ID` |
| Variable | `FOUNDRY_GUIDE_WEB_APP_NAME` |
| Variable | `FOUNDRY_GUIDE_WEB_APP_URL` |
| Secret | `AZURE_TENANT_ID` |
| Secret | `AZURE_SUBSCRIPTION_ID` |

The Azure federated credential subject must target:

```text
repo:<owner>/<repository>:environment:foundry-guide
```

Assign the workload identity **Website Contributor** on the App Service itself.
Don't grant it Contributor, Owner, or role-assignment permissions on the resource
group.

The workflow builds without environment access or OIDC, transfers a checksummed
seven-day artifact to a separate protected job, then uses OIDC to deploy it. Actions
are pinned to immutable commit SHAs. The workload identity stores no cloud or
publishing credential in GitHub.

## Deploy

Provision the infrastructure once with the repository owner's resource-tenant
account:

```bash
azd env set ENABLE_FOUNDRY_GUIDE true
azd env set ENABLE_FOUNDRY_GUIDE_WEB_APP true
azd env set FOUNDRY_GUIDE_WEB_AUTH_CLIENT_ID <app-client-id>
azd env set FOUNDRY_GUIDE_WEB_APP_SERVICE_SKU B1
azd up
```

Add the private `FOUNDRY_GUIDE_WEB_APP_URL` output to the app registration:

```text
<FOUNDRY_GUIDE_WEB_APP_URL>
```

Configure the GitHub Environment from the deployment outputs, assign its workload
identity the site-scoped role described above, then run **Deploy Foundry Guide
Web** from `main`. Do not publish the app URL or tenant/application identifiers.

Earlier preview deployments used a dedicated feedback storage account. After
deploying this version, remove that account and the
`FEEDBACK_STORAGE_TABLE_ENDPOINT` app setting; incremental ARM deployments don't
delete resources omitted from a newer template.

## View feedback

Open the deployment's Log Analytics workspace, select **Logs**, and run:

```kusto
AppEvents
| where TimeGenerated > ago(7d)
| where Name == "foundry_guide.feedback"
| extend
    rating = toint(Properties["feedback.rating"]),
    outcome = tostring(Properties["feedback.outcome"]),
    responseId = tostring(Properties["foundry_guide.response.id"]),
    agentName = tostring(Properties["foundry_guide.agent.name"]),
    channel = tostring(Properties["feedback.channel"])
| project TimeGenerated, rating, outcome, agentName, responseId, channel, OperationId
| order by TimeGenerated desc
```

Allow approximately five minutes for telemetry ingestion before treating feedback
events as missing.

The web app records `5` as helpful and `1` as not helpful. `OperationId` links the
event to its trace; `responseId` identifies the rated Foundry response. The event
doesn't contain the prompt, response text, explanation, or user identifier.
Outstanding feedback tokens become invalid if the single App Service instance
restarts; submitted feedback remains in Application Insights.

This application-owned event doesn't appear as a Foundry trace annotation as of
2026-07-15. Keep query results private because correlation identifiers are
operational data.

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

## Documentation Test History

### 2026-07-15
- Result: PASS with fixes
- Platform/Context: WSL2, isolated `azd` environment, Playwright MCP
- Notes:
  - Clean provisioning completed in 211 seconds; the initial ZIP deployment took 268 seconds.
  - Desktop and 390x844 mobile sign-in, chat, and feedback passed.
  - The feedback event appeared after 264 seconds, was trace-correlated in `AppEvents`, and contained no prompt, response text, explanation, or user identity.
  - Removed the blocked storage dependency and hardened the GitHub OIDC deployment boundary.
