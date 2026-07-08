# Runbook: experiencing Foundry Data security and governance

This runbook is for a lab that deliberately experiences the Microsoft Foundry →
Microsoft Purview **Data security and governance** path. It is not for RAG
authorization trimming; see [data-security-governance.md](data-security-governance.md)
for that boundary.

Use only synthetic data. Do not use customer data, Microsoft confidential data, or a
production tenant.

## What this enables

The path has several separate layers:

1. **Foundry toggle**: Foundry **Operate → Compliance → Data security and governance**
   sends Foundry model interaction data to the tenant's Purview account.
2. **Purview Audit / DSPM**: Purview surfaces audit/report/activity views after
   tenant-side prerequisites and latency.
3. **PAYG-backed policies**: Purview pay-as-you-go enables data security policies for
   enterprise AI apps beyond Audit-only visibility.
4. **DLP blocking**: blocking prompts is an app/policy integration path, not just a
   Foundry toggle.

## Account split

Use separate accounts intentionally:

| Account type | Use for |
| --- | --- |
| Foundry tester | Foundry portal, model calls, synthetic interactions, reading non-admin Purview views |
| Global admin | Purview PAYG link, Purview/Exchange role-group grants, tenant-wide setup |

Return to the Foundry tester for day-to-day testing after admin setup. Keep the
browser session open during the spike to avoid repeated MFA.

## Cost estimate for a small lab

There is no single "Foundry governance" meter. Expect several possible meters:

| Surface | Cost driver | Small-lab assumption |
| --- | --- | --- |
| Foundry model calls | Model input/output tokens | A few synthetic prompts; usually tiny compared with infra spend |
| Purview Audit for non-Microsoft AI apps | Audit records processed | One prompt and one response can create multiple records; confirm in Cost Management |
| Data Security for Gen AI Applications | Requests/messages for non-Microsoft 365 AI interactions | Count each synthetic prompt/response processed by Purview |
| Communication Compliance | Text records; 1 text record = 1,000 characters | Only if a communication-compliance policy evaluates the interaction |
| Data Lifecycle Management | Non-Microsoft AI app prompt/response interactions under retention policy | Only if retention is configured for Enterprise AI apps |
| eDiscovery | Storage/export for non-Microsoft AI data | Only if interactions are preserved/searched/exported |
| Insider Risk Management | Data security processing units | Only if IRM indicators/policies are enabled |
| In-transit protection | AI app/browser/network requests | Only if network/browser/SASE-style protections are enabled |

For this lab, keep volume to **10-20 short synthetic prompts** and avoid broad all-user
policies unless the UI requires them. Treat the estimate as **low but non-zero** until
Cost Management shows actuals. Use the [Microsoft Purview pricing page](https://azure.microsoft.com/pricing/details/purview/)
and the Azure pricing calculator for current unit prices; use Azure Cost Management
for actual spend.

## Enablement order

### 1. Deploy a minimal Foundry lab

Provision only what the test needs:

- Microsoft Foundry resource: `Microsoft.CognitiveServices/accounts`, kind
  `AIServices`
- Foundry project
- Model deployment

Avoid enabling unrelated observability, Foundry IQ/Search, Defender plans, or sample
data ingestion unless the test needs them.

### 2. Enable the Foundry → Purview toggle

As an account with **Foundry Account Owner**:

1. Open `https://ai.azure.com`.
2. Turn on **New Foundry** if needed.
3. Go to **Operate → Compliance → Data security and governance**.
4. Turn on **Enable Purview**.

Expected result after success: the pane changes from "not protected" to a Purview
coverage message for the subscription.

### 3. Establish tenant admin authority

Use Global Administrator only for the tenant/Purview setup steps that require it.
Either switch to a Global Admin account, or temporarily elevate the Foundry tester and
remove the elevation after the spike.

This is required before:

- managing Purview role groups
- linking PAYG billing
- completing some Purview setup actions

Live note: temporarily granting Global Administrator to the tester unlocked Purview
role-group management in the existing browser session.

### 4. Fix Purview roles

As Global Administrator or an account that can manage Purview role groups:

1. Open **Microsoft Purview → Settings → Roles and scopes → Role groups**.
2. Grant the Foundry tester only the missing roles needed for the next test.

Minimum roles to consider:

| Need | Role/group |
| --- | --- |
| View DSPM for AI | Entra Compliance Administrator or Purview Compliance Administrator |
| Manage role groups | Role Management via Organization Management, or Global Administrator |
| Activate Audit get-started step | Exchange role groups listed by the DSPM permissions doc |
| View prompts/responses in Activity Explorer | Microsoft Purview Data Security AI Content Viewer first; Content Explorer Content Viewer only if needed |
| View AI Visits / user risk levels | Insider Risk Management Analyst or Investigator |

Live note: after a temporary Global Administrator grant, **Settings → Roles and
scopes → Role groups** unlocked, and adding the tester to **Data Security AI Content
Viewers** increased that role group's user count from 0 to 1.

### 5. Link PAYG billing

As Global Administrator:

1. Open **Purview → Usage center → Pay-as-you-go**.
2. Select **Get started**.
3. Link the tenant to an Azure subscription and resource group.

This is the billing boundary. After this step, PAYG-backed Purview features can emit
charges when policies process data.

Live note: with only Compliance Administrator, **Get started** hung on "Loading...".
After a temporary Global Administrator grant, the backend accepted tenant provisioning
with HTTP `202`, created a `Microsoft.Purview/tenantAccounts` tenant account in
`westus`, and showed `isEligibleForUpgrade:true`. After the async setup finished, the
UI returned to "Your Azure subscription isn't linked for billing," so tenant-account
provisioning and subscription billing link are separate steps.

When linking the subscription, use a dedicated resource group and a non-default
resource name:

- Resource group pattern: a dedicated lab group in a PAYG-eligible region, for
  example `rg-purview-payg-lab`
- Resource name pattern: a deliberate non-default Purview account name, for example
  `purview-payg-lab-<suffix>`

The portal auto-filled a default resource name (`Contoso`) and then blocked with:
"Default names aren't allowed for linked resources in your org's tenant. Enter a new
resource name." After replacing it, **Confirm** created a
`Microsoft.Purview/accounts` resource in the selected resource group. The portal then
showed **Upgrading** while Azure reported the account as `Creating`. After
provisioning completed, the portal showed **Congratulations!** and said the Azure
subscription was successfully linked to the tenant. Azure reported the
`Microsoft.Purview/accounts` resource as `Succeeded`.

### 6. Activate Purview Audit

As an account with the required Purview/Exchange roles:

1. Open **Purview → DSPM for AI (classic) → Overview**.
2. Select **Activate Microsoft Purview Audit**.
3. Click the final **Activate Purview Audit** action.

Do this after role setup. If it fails, check the Exchange/Purview role groups from the
DSPM permissions doc before retrying. Then wait; Activity Explorer can say detection
takes **24 hours or more**.

Live note: after PAYG was linked and the tester had temporary Global Administrator,
the final **Activate Purview Audit** action still failed. The browser console showed
`POST /api/adminauditlogconfig/EnableUnifiedAuditLogIngestion` returning HTTP `500`.

### 7. Create the enterprise AI app capture path

In **Purview → DSPM for AI (classic) → Recommendations**, use the recommendations in
this order:

1. **Secure data in Azure AI apps and agents**
2. **Secure interactions from enterprise AI apps**

These are the Foundry-relevant recommendations. They are distinct from browser,
endpoint, SASE, or Microsoft 365 Copilot recommendations.

This depends on PAYG being linked. If recommendations stay stuck in loading or don't
show policy actions, return to the PAYG and role steps first.

Live note: after PAYG linked, the classic Recommendations page still loaded slowly
and then said recommendations are now in the unified DSPM experience. The page offered
**Take me there**. Earlier, the unified DSPM prompt warned that entering it can turn
on DLP and Insider Risk Management analytics.

In unified DSPM, **Secure data in Azure AI apps and agents** did not create a Purview
policy directly. It opened a remediation panel that sends you to Microsoft Defender
for Cloud:

1. Go to **Defender for Cloud → Management → Environment settings**.
2. Select the Azure AI subscription.
3. Under **Cloud Workload Protection**, turn on **AI workloads** if needed.
4. Open **Settings** for AI workloads.
5. Turn on **Enable data security for AI interactions**.
6. Continue and save.

The panel says this requires Security Admin, Contributor, or Azure subscription Owner
permissions, and that detection/reporting can take at least 24 hours after setup.

Live note: the same setting can be inspected through the Defender for Cloud pricing
resource `Microsoft.Security/pricings/AI`. Enabling the AI plan set
`pricingTier: Standard` with extensions:

- `AIPromptEvidence`: `True`
- `AIPromptSharingWithPurview`: `True` (the Purview data-security capture component)
- `AIModelScanner`: `False`

The plan reported `resourcesCoverageStatus: FullyCovered`.

Live note: unified DSPM then required a **Complete setup to unlock the unified DSPM
experience** step. It said setup turns on auditing, analytics, and AI collection
policies in one step. The dialog warned that the account still didn't have the
permissions needed to turn on auditing, but setup could continue and Audit could be
turned on later. After approval, setup completed and showed **Congrats, you've
completed your setup tasks**.

### 8. Generate synthetic Foundry activity

Use the repo's existing Foundry-native agent creation path, then the documented
conversation/response flow:

```bash
eval "$(azd env get-values)"

./scripts/create-agent.sh \
  --endpoint "$PROJECT_ENDPOINT" \
  --project "$PROJECT_NAME" \
  --model "$MODEL_DEPLOYMENT_NAME" \
  --name purview-lab-agent \
  --instructions "You are a Microsoft Foundry and Purview data security lab assistant. Use only synthetic Contoso/Fabrikam data and never request or output secrets." \
  --description "Synthetic Purview lab agent"
```

Then create a conversation and response using the Foundry project endpoint (not the
legacy `openai.azure.com` endpoint):

```bash
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)
MARKER="PURVIEW-FOUNDRY-LAB-YYYY-MM-DD-001"

CONV_RESPONSE=$(jq -n --arg marker "$MARKER" '{
  items: [{
    type: "message",
    role: "user",
    content: ("Synthetic post-capture marker " + $marker + ": summarize that Fabrikam Project Cedar is mock data and contains no real customer data, production data, secrets, or Microsoft confidential data.")
  }]
}' | curl -fsS -X POST "$PROJECT_ENDPOINT/conversations?api-version=v1" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @-)

CONV_ID=$(echo "$CONV_RESPONSE" | jq -r .id)

jq -n --arg conversation "$CONV_ID" '{
  conversation: $conversation,
  agent_reference: {
    type: "agent_reference",
    name: "purview-lab-agent",
    version: "1"
  }
}' | curl -fsS -X POST "$PROJECT_ENDPOINT/openai/v1/responses" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @- > response.json
```

Run a few short prompts with unique markers, for example:

```text
PURVIEW-FOUNDRY-LAB-YYYY-MM-DD-001
This is synthetic Contoso/Fabrikam lab data. It contains no real customer data,
production data, or Microsoft confidential data.
```

If testing sensitive-information detection, use obviously synthetic examples only.
Do not paste real secrets, real IDs, or customer data.

Generate activity **after** the capture path exists. Any prompts sent before Audit /
capture policy setup are useful smoke tests but might not appear in Purview reports.
Save the Foundry Responses API JSON and verify the marker without printing prompt or
response content:

```bash
./scripts/verify-agent-run.sh \
  --expect-text PURVIEW-FOUNDRY-LAB-YYYY-MM-DD-001 \
  < response.json
```

`scripts/verify-agent-run.sh --self-test` validates the local verifier without
calling Azure.

Live note: a post-capture run using `scripts/create-agent.sh`, the Foundry-native
conversation/response endpoints, and marker `PURVIEW-FOUNDRY-LAB-2026-07-09-001`
returned a completed response. `scripts/verify-agent-run.sh --expect-text` returned
`pass`.

### 9. Observe Purview

Check:

- **DSPM for AI → Reports**
- **DSPM for AI → Activity explorer**
- **Audit** search
- Optional, if configured: **Data Lifecycle Management**, **eDiscovery**, or
  **Communication Compliance**

Filter for Enterprise AI apps / Azure AI / the synthetic marker where available.

Immediate live observation after setup and one post-capture synthetic response:
unified DSPM **Activity explorer** still showed **0 items / No data available**.
This is expected to be inconclusive because the portal itself says detection/reporting
can take 24 hours or more.

## DLP blocking path

DLP blocking for Foundry is not proven by the Foundry toggle alone.

For app-layer blocking, expect:

1. PAYG enabled.
2. Entra app registration.
3. Admin consent for Microsoft Graph permissions such as `Content.Process.User`.
4. A DLP rule scoped to the registered AI app.
5. App code that calls Graph `processContent` and honors the returned verdict.

If a managed Foundry path appears in the portal, document exactly what it provisions
before assuming it replaces the app-layer Graph integration.

## Gotchas observed live

- Learn said the Purview toggle was under **Security posture**, but the live portal
  showed it under a separate **Data security and governance** tab.
- **Security posture** was Defender for Cloud only and showed Defender enablement
  actions. Do not confuse this with Purview.
- The Foundry toggle did not prompt for PAYG. PAYG is a separate Purview Usage center
  step.
- Entra **Compliance Administrator** could view parts of DSPM for AI but could not
  manage Purview role groups.
- Purview role-group management tabs were disabled without Role Management / Global
  Admin authority.
- Temporarily granting Global Administrator to the tester unlocked role-group
  management in the existing browser session; remove temporary elevation after the
  spike.
- The **Data Security AI Content Viewers** role group is the narrower first role for
  viewing AI interaction content; adding the tester changed its user count from 0 to
  1.
- **Activate Purview Audit** opened but failed with a generic "try again later" error
  when the tester lacked the required Exchange/Purview role groups.
- Activity Explorer loaded but reported missing permissions for AI Visits and user
  risk levels.
- Activity Explorer can show no data and warn that detection can take 24 hours or
  more.
- PAYG **Get started** can hang on "Loading..." if the tenant is not registered or
  the account lacks the right admin authority. In one live run, the backend reported
  `TenantNotFound`, `hasValidSubscription:false`, and `hasEnterpriseAccount:false`.
- PAYG setup can succeed only partially: tenant-account provisioning can complete
  (`Microsoft.Purview/tenantAccounts`, `westus`) while the Usage Center still says
  the Azure subscription is not linked for billing.
- PAYG subscription linking uses an Azure `Microsoft.Purview/accounts` resource, not
  only an invisible tenant setting. In the live lab, the portal registered
  `Microsoft.Purview` and `Microsoft.Storage` providers, waited for provider
  registration, then created a named `Microsoft.Purview/accounts` resource.
- Do not accept a default resource name in the PAYG link dialog; tenants can reject
  default names. Use a deliberate lab name and document it.
- A successful PAYG link can still leave **Activate Purview Audit** failing with a
  backend HTTP `500`; treat Audit activation as a separate service gate, not proof
  that PAYG failed.
- Classic DSPM for AI recommendations can redirect to unified DSPM. Treat that as a
  product-surface migration, not a Foundry-specific issue.
- The unified DSPM **Secure data in Azure AI apps and agents** action routes through
  Microsoft Defender for Cloud AI workload settings. This is a Defender/security-plane
  dependency, not just a Purview configuration screen.
- The Defender API names for this path are not obvious from the portal labels:
  `Microsoft.Security/pricings/AI` enables the AI workload plan, and
  `AIPromptSharingWithPurview` maps to "Enable data security for AI interactions."
- Unified DSPM setup can complete even while Audit activation remains blocked; the
  setup dialog explicitly says Audit can be turned on later if the current account
  lacks audit permissions.
- Do **not** use **Cognitive Services OpenAI User** as a shortcut for Microsoft
  Foundry access. Microsoft Learn explicitly says not to assign built-in roles that
  start with **Cognitive Services** for Foundry scenarios; use **Foundry User** /
  **Foundry Owner** or narrower Foundry roles instead. In the live lab, this role was
  mistakenly added while troubleshooting a legacy `openai.azure.com` call and then
  removed.
- For repeatable Foundry activity, use `scripts/create-agent.sh` for agent creation
  and the Foundry project endpoint `...services.ai.azure.com/api/projects/...` with
  `/conversations?api-version=v1` and `/openai/v1/responses`. Do not switch to the
  legacy `openai.azure.com` chat-completions endpoint for this runbook.
- `scripts/verify-agent-run.sh` now supports two evidence modes: MCP/tool-call
  validation by default, and marker validation for plain synthetic responses via
  `--expect-text` or `--expect-regex`.
- The Purview portal welcome / classic-portal popups can block the page and may need
  to be dismissed before continuing.

## Stop conditions

Stop and reassess if:

- The UI asks to enable Defender plans.
- The UI asks to turn on Adaptive Protection or broad Insider Risk policies.
- A policy defaults to all users and captures content broadly.
- The next step requires secrets/client secrets.
- Cost Management shows unexpected Purview spend.

Prefer one narrow synthetic policy over broad tenant-wide policy whenever the portal
allows scoping.
