# Foundry Guide feedback loop

Optional sample for issue #66: a simple prompt agent, app-emitted OpenTelemetry feedback, and aggregate negative-feedback issues.

## Enable it

```bash
azd env set ENABLE_OBSERVABILITY true
azd env set ENABLE_FOUNDRY_GUIDE true
azd up
```

The post-provision hook creates or reuses the `foundry-guide` prompt agent. The endpoint is protected by Microsoft Entra ID; callers need Foundry data-plane access.

## Try it

```bash
./scripts/foundry-guide-chat.sh --prompt "What is the difference between Microsoft Foundry and Foundry classic?" --rating 5
```

The client calls the agent and emits `gen_ai.evaluation.result` to Application Insights. It records rating metadata and trace context, not prompts, responses, explanations, user identifiers, secrets, or Azure deployment identifiers.

Limitation: feedback is collected by this sample client, not the Foundry Playground. Playground conversations can appear in traces, but this sample's 5-point/good-bad ratings are only emitted when the client is used.

## GitHub issue automation

The manual workflow is opt-in. Configure these repository settings, then set `FOUNDRY_GUIDE_FEEDBACK_ENABLED=true`:

Deployment caution: before enabling this for more users or confidential conversations, decide where issues should be created. Prefer an internal or GitHub Enterprise Managed User repository, and keep issue payloads aggregate-only even there.

| Setting | Purpose |
| --- | --- |
| `vars.AZURE_CLIENT_ID` | Existing OIDC app registration client ID |
| `secrets.AZURE_TENANT_ID` | Tenant for Azure login |
| `secrets.AZURE_SUBSCRIPTION_ID` | Subscription for Azure login |
| `vars.FOUNDRY_GUIDE_RESOURCE_GROUP` | Resource group containing Application Insights |
| `vars.FOUNDRY_GUIDE_APPLICATION_INSIGHTS_NAME` | Application Insights component name |

Optional variables: `FOUNDRY_GUIDE_AGENT_NAME`, `FOUNDRY_GUIDE_FEEDBACK_LOOKBACK`, `FOUNDRY_GUIDE_MIN_NEGATIVE_FEEDBACK`, and `FOUNDRY_GUIDE_FEEDBACK_DRY_RUN`. Set `FOUNDRY_GUIDE_FEEDBACK_DRY_RUN=true` to validate the query without creating or commenting on issues.

The workflow uses OIDC for Azure and `GITHUB_TOKEN` for issues; no PAT is required. Set `FOUNDRY_GUIDE_FEEDBACK_PRINCIPAL_ID` before `azd up` to grant the workflow principal read-only monitoring access.

If the aggregate negative-feedback threshold is met, `scripts/create-feedback-issue.sh` creates or updates one deduplicated issue.
