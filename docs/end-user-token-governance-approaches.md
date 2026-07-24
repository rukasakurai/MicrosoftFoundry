# End-user token governance approaches

Organizations that expose shared AI capacity need to attribute usage to a
consumer, keep that consumer within an entitlement or budget, and show what was
used without granting access to the underlying Azure resources.

> As an AI platform owner, I want per-consumer usage reporting and limits so
> teams can share a model deployment without losing cost accountability or
> allowing one consumer to exhaust the available budget.

This need includes several related but different problems:

- **Showback or chargeback:** report usage by team, application, tenant, or user.
- **Rate protection:** limit short-term tokens per minute.
- **Budget enforcement:** cap tokens or cost over a day or month.
- **Consumer self-service:** show a caller its own usage without exposing other
  consumers' records.
- **Strict entitlement:** prevent concurrent requests from spending more than
  the remaining allowance.
- **Operator governance:** alert, suspend, or reroute consumers when a threshold
  is crossed.

The eight approaches below address different combinations of those needs. The
first three have runnable implementations in the separate
`azure-ai-token-governance` repository.
The other five are public Microsoft-managed reference implementations reviewed
as of 2026-07-23.

Some external samples support Azure OpenAI or multiple model providers rather
than the `Microsoft.CognitiveServices/accounts` Microsoft Foundry architecture
used here. Their APIM and Azure Monitor patterns are relevant, but their
infrastructure should not be treated as Microsoft Foundry IaC without checking
the resource provider and endpoint.

## Important variations

| Decision | Variations |
| --- | --- |
| Consumer identity | APIM subscription, Entra user, application, tenant, product, or business unit |
| Unit | Requests, tokens, cost, or a model-specific multiplier |
| Time window | Per minute, hour, day, month, or billing period |
| Result audience | Operator dashboard, consumer API, or automated policy |
| Consistency | Delayed telemetry, pre-call check, or atomic reservation |
| Concurrency guarantee | Possible overshoot, bounded overshoot, or no oversubscription |
| Query trust | Caller has Azure Monitor RBAC, or a trusted layer fixes and scopes the query |
| Runtime footprint | APIM only, APIM plus query API, or APIM plus a durable policy engine |

## Comparison

| # | Approach | Primary need | Enforcement guarantee | Usage interface |
| ---: | --- | --- | --- | --- |
| 1 | Standalone sample: simple + App Service | Consumer quota and self-service history | APIM-native; telemetry is delayed | Consumer API backed by Log Analytics |
| 2 | Standalone sample: APIM-only | Same simple behavior without query compute | APIM-native; telemetry is delayed | APIM policy queries Log Analytics |
| 3 | Standalone sample: strict ledger | No concurrent oversubscription | Atomic pre-call reservation | Consumer API backed by the enforcement ledger |
| 4 | Azure-Samples AI-Gateway FinOps framework | Product budgets and automated suspension | APIM quota plus delayed cost automation | Workbooks and alerts |
| 5 | Azure-Samples APIM costing | Business-unit showback and chargeback | Reporting only | KQL and workbook |
| 6 | Azure AI Gateway landing zone | Enterprise access-contract enforcement | APIM-native token quota | Response variables and telemetry |
| 7 | Azure-Samples AI Gateway Dev Portal | Operator analytics and exploration | Reporting only | Browser queries Azure Monitor directly |
| 8 | Azure-Samples AI Policy Engine | SaaS plans, routing, billing, and pre-checks | Pre-call check; not an atomic reservation | Custom API and dashboard |

## Standalone sample implementations

### 1. Simple enforcement with an App Service usage API

```text
Chat:  Client -> APIM llm-token-limit -> Foundry
Usage: Client -> APIM -> App Service -> Log Analytics
```

APIM identifies the consumer by `context.Subscription.Id`, enforces
`llm-token-limit`, invokes Foundry with managed identity, and returns consumed
and remaining token headers. APIM diagnostics asynchronously write token usage
to `ApiManagementGatewayLlmLog`.

The App Service exposes `GET /token-usage/simple/usage`. It receives the trusted
APIM subscription ID and runs fixed KQL that joins the LLM and gateway tables by
`CorrelationId`.

**Use when:** consumers need a stable usage API and application code is
acceptable.

**Boundary:** enforcement is immediate, but history reflects Azure Monitor
ingestion delay and concurrent APIM requests can overshoot.

### 2. Simple enforcement with an APIM-only usage API

```text
Chat:  Client -> APIM llm-token-limit -> Foundry
Usage: Client -> APIM send-request -> Log Analytics
```

This implementation preserves the simple enforcement model but removes App
Service from the usage path. The APIM policy:

1. obtains a Log Analytics token with APIM's managed identity;
2. builds fixed KQL containing `context.Subscription.Id`;
3. calls the Log Analytics Query API with `send-request`; and
4. returns the normalized usage result.

Callers cannot submit arbitrary KQL. APIM has Log Analytics Reader, while
consumers receive no Azure Monitor RBAC.

**Use when:** simple quota headers and consumer history are required, but a
separate query service is not.

**Boundary:** this reduces infrastructure, not telemetry delay or quota
overshoot. Complex query transformation and error handling now live in APIM
policy expressions.

### 3. Strict authoritative reservation ledger

```text
Client -> APIM -> App Service -> reserve in Table Storage
                            -> Foundry
                            -> settle actual usage in Table Storage
```

The App Service atomically reserves a conservative maximum before invoking
Foundry. Concurrent requests that cannot reserve the full amount are rejected.
After a successful response, the service replaces the reservation with
Foundry's reported usage. The same ledger serves
`GET /token-usage/strict/usage`.

Expired reservations and failures that may have reached Foundry are charged at
the reserved maximum. This favors enforcement safety over exact billing during
ambiguous failures.

**Use when:** prepaid, contractual, or financial limits must not be exceeded
under concurrency.

**Boundary:** custom compute and a durable ledger add latency and operations.
Conservative reservations can temporarily reject requests that would have fit
after settlement.

## Microsoft-managed reference implementations

### 4. Azure-Samples AI-Gateway FinOps framework

[`Azure-Samples/AI-Gateway/labs/finops-framework`](https://github.com/Azure-Samples/AI-Gateway/tree/main/labs/finops-framework)
applies per-product `llm-token-limit` policies, emits token metrics, maintains
pricing and subscription-quota custom tables, and provides Azure Monitor
Workbooks. A scheduled query alert and Logic App can disable an APIM
subscription after its calculated cost exceeds a budget.

**Variation addressed:** operator-managed cost budgets and automated
remediation across products.

**Boundary:** budget automation depends on ingested telemetry. It is not an
atomic per-request cost reservation and does not expose a consumer usage API.

Relevant files:

- [`main.bicep`](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/finops-framework/main.bicep)
- [`policy.xml`](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/finops-framework/policy.xml)

### 5. Azure-Samples APIM costing

[`Azure-Samples/Apim-Samples/samples/costing`](https://github.com/Azure-Samples/Apim-Samples/tree/main/samples/costing)
focuses on showback and chargeback. Its KQL joins
`ApiManagementGatewayLlmLog` with `ApiManagementGatewayLogs` on
`CorrelationId`, then uses `ApimSubscriptionId` as the business-unit key.

**Variation addressed:** usage attribution and reporting where enforcement is
handled elsewhere or is not required.

**Boundary:** this is an analytics pattern, not a token quota implementation.

Relevant file:

- [`bu-token-usage.kql`](https://github.com/Azure-Samples/Apim-Samples/blob/main/samples/costing/queries/bu-token-usage.kql)

### 6. Azure AI Gateway landing zone access contracts

[`Azure/terraform-ai-gateway-landing-zone`](https://github.com/Azure/terraform-ai-gateway-landing-zone)
includes a default AI product policy with per-subscription tokens-per-minute and
monthly token quota settings. The policy is part of a broader access-contract
model that also constrains allowed models.

**Variation addressed:** standardized enterprise entitlements configured as
APIM products and subscriptions.

**Boundary:** it demonstrates enforcement policy, not a consumer-readable usage
history API or an external authoritative ledger.

Relevant file:

- [`default-ai-product-policy.xml`](https://github.com/Azure/terraform-ai-gateway-landing-zone/blob/main/modules/access-contracts/policies/default-ai-product-policy.xml)

### 7. Azure-Samples AI Gateway Dev Portal

[`Azure-Samples/ai-gateway-dev-portal`](https://github.com/Azure-Samples/ai-gateway-dev-portal)
is a browser portal for APIM operators. Its token analytics pages build KQL over
`ApiManagementGatewayLlmLog` and `ApiManagementGatewayLogs`, then call the
resource-scoped Azure Monitor logs endpoint using the signed-in user's Azure
credential.

**Variation addressed:** rich interactive analytics for trusted users who
already have Azure RBAC.

**Boundary:** Log Analytics has no per-row authorization by
`ApimSubscriptionId`. This pattern is appropriate for operators, not isolated
untrusted consumers unless Azure resource access is partitioned.

Relevant files:

- [`Tokens.tsx`](https://github.com/Azure-Samples/ai-gateway-dev-portal/blob/main/src/pages/Tokens.tsx)
- [`azure.ts`](https://github.com/Azure-Samples/ai-gateway-dev-portal/blob/main/src/services/azure.ts)

### 8. Azure-Samples AI Policy Engine

[`Azure-Samples/ai-policy-engine`](https://github.com/Azure-Samples/ai-policy-engine)
places a .NET policy engine behind APIM. Before forwarding a request, APIM calls
`/api/precheck` to validate the client plan, model access, rate limits, and
current quota. After the model response, APIM sends usage to `/api/log`
asynchronously. Cosmos DB stores durable records and Redis provides a hot cache.

**Variation addressed:** multi-tenant SaaS plans, model routing, billing,
dashboards, and centralized policy decisions.

**Boundary:** the pre-check reads current usage but does not atomically reserve
the prospective request. Concurrent requests can pass before their usage is
recorded, so this is not equivalent to the strict standalone implementation.

Relevant files:

- [`entra-jwt-policy.xml`](https://github.com/Azure-Samples/ai-policy-engine/blob/main/policies/entra-jwt-policy.xml)
- [`PrecheckEndpoints.cs`](https://github.com/Azure-Samples/ai-policy-engine/blob/main/src/AIPolicyEngine.Api/Endpoints/PrecheckEndpoints.cs)

## Case study: showing usage in Foundry Guide

Foundry Guide authenticates users in its web app, then its .NET backend calls
the Foundry agent endpoint directly. This repository uses a Guide-owned
adaptation of approach 3 so the frontend receives authoritative per-user usage
without routing the application through APIM. The alternatives remain relevant
when the desired UX or operational constraints differ.

| Approach | Preference profile that makes it the best fit |
| --- | --- |
| 1. Simple + App Service | Prefer .NET and a frontend-specific `/api/usage` contract; reuse the existing App Service; require server-side user isolation and flexible history; accept Log Analytics delay and no atomic enforcement. |
| 2. APIM-only | Minimize application code; already accept APIM cost; prefer managed services and policy expressions; accept eventual consistency and more policy complexity. Route agent traffic through APIM and attribute it to the authenticated user. |
| 3. Strict ledger | Require immediate authoritative `used`, `reserved`, and `remaining` values; concurrent overspending is unacceptable; prefer .NET; accept ledger code, Storage cost, added latency, and conservative failure charging. |
| 4. FinOps framework | Want an operator budget experience with cost-based alerts and automated suspension across teams or products; prefer Workbooks and Logic Apps over an in-chat meter; accept delayed remediation and threshold overshoot. |
| 5. APIM costing | Need visualization, showback, or chargeback only; prefer KQL and Workbooks; want little new runtime infrastructure; accept telemetry delay and no enforcement. Add a trusted API only if ordinary users need isolated self-service data. |
| 6. Landing-zone access contracts | Prefer Terraform and standardized enterprise APIM products, subscriptions, model allowlists, and quota policies; want quota headers and rejection messages more than detailed history; prioritize consistency across environments. |
| 7. AI Gateway Dev Portal | Users are trusted Azure operators who may hold Azure Monitor RBAC; prefer React/TypeScript and a ready-made analytics UI; want rich token, request, latency, and log exploration rather than consumer isolation or enforcement. |
| 8. AI Policy Engine | Token usage belongs in a broader multi-tenant SaaS control plane with plans, billing, routing, dashboards, and rate limits; prefer .NET; accept Cosmos DB, Redis, Container Apps, higher cost, and possible concurrent overshoot. |

For APIM-based choices, Foundry Guide's agent calls must first pass through APIM,
and APIM token accounting for that agent endpoint must be verified. For
Log Analytics choices, a trusted backend or APIM policy must scope results
before showing them to ordinary users; Log Analytics does not provide row-level
authorization by application user.

### Illustrative monthly Azure cost

The following estimates use public Japan East prices queried on
2026-07-24 at 08:28 JST. They are marginal to the existing Foundry Guide:

- 10,000 agent requests and 100 users per month;
- 0.1 GB/month of new metadata-only telemetry;
- the existing B1 App Service and Log Analytics workspace are reused; and
- model tokens are excluded because they are common to all approaches.

| Approach | Additional USD/month |
| --- | ---: |
| 1. Simple + App Service | **$48.40**, or **$62.20** with a separate B1 plan |
| 2. APIM-only | **$48.40** |
| 3. Strict ledger | **< $0.10** without APIM; **~$48.10** with APIM |
| 4. FinOps framework | **$51.40** |
| 5. APIM costing | **$48.40** |
| 6. Landing-zone access contracts | **$48.40** for the access-contract pattern; **$990-$1,050** for the default enterprise landing zone |
| 7. AI Gateway Dev Portal | **$48.40** embedded or free-hosted; **$57.40** with Static Web Apps Standard |
| 8. AI Policy Engine | **~$15** integrated into the existing App Service; **~$69** with its Container App stack but no APIM; **~$769** for the sample's default deployment |

The main meter assumptions are APIM Developer at $48.03/month, Linux App
Service B1 at $13.87/month, Log Analytics ingestion at $3.34/GB, two
five-minute FinOps log alerts at $3/month, and Static Web Apps Standard at
$9/month. The default AI Policy Engine estimate includes approximately $700
for APIM Standard v2, $34 for Container Apps, $14.60 for Managed Redis B0,
and $20.28 for Container Registry Standard.

APIM Consumption cannot replace Developer for these implementations: it does
not provide APIM resource logs, and
[`llm-token-limit`](https://learn.microsoft.com/azure/api-management/llm-token-limit-policy)
does not support the Consumption tier as of 2026-07-24. Developer has no
production SLA. Replacing it with Basic v2 raises the APIM component to about
$150/month; Standard v2 is about $700/month.

At 100 times the assumed traffic and 10 GB/month of telemetry, Log Analytics
ingestion rises to about $33.40/month while fixed APIM cost remains dominant.
Prices come from the
[Azure Retail Prices API](https://prices.azure.com/api/retail/prices); these
are scenario estimates, not actual billed costs.

### Illustrative code review surface

The estimates below count hand-maintained, nonblank application, test, IaC,
policy, script, configuration, notebook, and documentation lines as of
2026-07-24. Generated output, lockfiles, and transitive package source are
excluded. OSS source is included when it would be copied or substantially
adapted.

All numeric columns use **k lines of code (LOC)** and are right-aligned.
“Relevant sample” is the focused implementation subtree; “expanded reference”
includes shared modules or the full repository where that materially changes
the review surface.

| Approach | Owned implementation (k LOC) | Relevant sample (k LOC) | Expanded reference (k LOC) |
| --- | ---: | ---: | ---: |
| 1. Simple + App Service | **0.7-1.1k** | — | — |
| 2. APIM-only | **0.5-0.9k** | — | — |
| 3. Strict ledger | **1.2-1.8k** | — | — |
| 4. FinOps framework | **2.0-4.0k** | **9.8k** | **29.6k** |
| 5. APIM costing | **0.5-1.0k** | **6.1k** | **6.1k** |
| 6. Landing-zone access contracts | **0.8-1.5k** | **2.1k** | **173.2k** |
| 7. AI Gateway Dev Portal | **3.0-6.0k** | **20.2k** | **20.2k** |
| 8. AI Policy Engine | **8.0-15.0k** | **22.7k** | **76.8k** |

The standalone repository's combined implementation of approaches 1-3 is **3.1k LOC**:
1.5k C#, 0.8k Bicep, 0.4k shell automation, 0.3k documentation, and less than
0.1k project configuration. The individual estimates are not additive because
the approaches share infrastructure, contracts, scripts, and documentation.

By minimum code owned, the order is approximately: APIM-only, APIM costing,
simple + App Service, landing-zone access contracts, strict ledger, FinOps,
Dev Portal, then AI Policy Engine. By reference review surface, the full
landing zone is the clear outlier.

LOC is not proportional to risk. The strict ledger has fewer lines than several
dashboard approaches, but its concurrency, settlement, expiry, and
failure-charging logic is more correctness-critical per line. Workbook JSON is
less algorithmically dense, while policy XML, KQL, and IaC can create large
security or reliability effects in relatively few lines.

## Selection guide

| Requirement | Smallest fitting approach |
| --- | --- |
| APIM quota headers only | APIM `llm-token-limit`, as in approach 6 |
| Consumer history without separate compute | Approach 2 |
| Consumer history behind an application API | Approach 1 |
| Operator showback or chargeback | Approach 5 or 7 |
| Product cost budgets and automated suspension | Approach 4 |
| Rich SaaS plans, routing, and billing | Approach 8 |
| No oversubscription under concurrent requests | Approach 3 |

No Microsoft-managed sample found in this review implements either the
APIM-managed-identity Log Analytics proxy in approach 2 or the atomic
reserve-and-settle ledger in approach 3.
