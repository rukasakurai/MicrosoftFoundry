# Foundry Guide feedback loop

This optional sample demonstrates issue #66: a simple Microsoft Foundry prompt agent, end-user ratings emitted as OpenTelemetry, and aggregate negative feedback turned into a deduplicated GitHub issue.

## Enable it

```bash
azd env set ENABLE_OBSERVABILITY true
azd env set ENABLE_FOUNDRY_GUIDE true
azd up
```

`azd up` provisions the Foundry account/project/model and Application Insights, then the post-provision hook creates a prompt agent named `foundry-guide`. The endpoint is protected by Microsoft Entra ID; callers need the Foundry data-plane role used by the baseline, such as Foundry User or a narrower consumer role when assigned separately.

## Try it

```bash
./scripts/foundry-guide-chat.sh --prompt "What is the difference between Microsoft Foundry and Foundry classic?" --rating 5
```

The client calls the agent through the project endpoint and emits a `gen_ai.evaluation.result` OpenTelemetry event to Application Insights. It records the rating, agent name, agent version, and trace context; it does not record prompts, responses, feedback explanations, user identifiers, secrets, or Azure deployment identifiers.

Limitation: feedback is collected by this sample client, not the Foundry Playground. Playground conversations can appear in traces, but this sample's 5-point/good-bad ratings are only emitted when the client is used.

## GitHub issue automation

The scheduled workflow is opt-in. Configure these repository settings, then set `FOUNDRY_GUIDE_FEEDBACK_ENABLED=true`:

| Setting | Purpose |
| --- | --- |
| `vars.AZURE_CLIENT_ID` | Existing OIDC app registration client ID |
| `secrets.AZURE_TENANT_ID` | Tenant for Azure login |
| `secrets.AZURE_SUBSCRIPTION_ID` | Subscription for Azure login |
| `vars.FOUNDRY_GUIDE_RESOURCE_GROUP` | Resource group containing Application Insights |
| `vars.FOUNDRY_GUIDE_APPLICATION_INSIGHTS_NAME` | Application Insights component name |

Optional variables: `FOUNDRY_GUIDE_AGENT_NAME`, `FOUNDRY_GUIDE_FEEDBACK_LOOKBACK`, `FOUNDRY_GUIDE_MIN_NEGATIVE_FEEDBACK`, and `FOUNDRY_GUIDE_FEEDBACK_DRY_RUN`. Set `FOUNDRY_GUIDE_FEEDBACK_DRY_RUN=true` to validate the query without creating or commenting on issues.

For Azure access, the workflow uses OIDC, not a GitHub PAT. If the workflow service principal should be configured by this template, set `FOUNDRY_GUIDE_FEEDBACK_PRINCIPAL_ID` in the azd environment to that service principal's object ID before `azd up`; the template grants read-only monitoring roles on Application Insights and Log Analytics.

The workflow queries aggregate negative ratings only. If the threshold is met, `scripts/create-feedback-issue.sh` creates or comments on one open issue titled `Aggregate negative feedback for Foundry Guide`.
