# End-user token usage

This opt-in sample implements three consumer-scoped token quota approaches behind
one Azure API Management subscription.

See [End-user token governance approaches](end-user-token-governance-approaches.md)
for the business scenarios and comparison with Microsoft-managed samples.

| Approach | Enforcement | Usage source | Guarantee |
| --- | --- | --- | --- |
| Simple | APIM `llm-token-limit` | APIM LLM logs in Log Analytics | Immediate response headers; delayed usage history |
| APIM-only | APIM `llm-token-limit` | APIM policy queries Log Analytics | Simple behavior without App Service |
| Strict | Atomic reservation and settlement in Azure Table Storage | The enforcement ledger | Current committed and reserved usage |

`Quota By Counter Keys` is not used because it reads `quota-by-key` call and
bandwidth counters, not `llm-token-limit` token counters.

## Deploy

The sample requires .NET 10 and provisions Developer-tier APIM, which can take
30 minutes or longer to deploy.

```bash
azd env new token-usage-e2e
azd env set ENABLE_TOKEN_USAGE_SAMPLE true
azd env set ENABLE_OBSERVABILITY true
azd env set ENVIRONMENT_PURPOSE token-usage-e2e
azd env set ENVIRONMENT_LIFECYCLE ephemeral
azd env set ENVIRONMENT_WORKSTREAM issue-89
azd up
```

The existing Foundry account, model deployment, Log Analytics workspace, and
Application Insights component are reused. The sample adds:

- Developer-tier APIM with one product and test subscription
- APIM LLM diagnostics and token metrics
- A .NET 10 App Service reachable only from that APIM instance
- Azure Table Storage for the authoritative ledger
- Managed-identity roles for Foundry inference, Log Analytics queries, and
  table data

The APIM API diagnostics management property used to enable LLM token logs is
preview as of 2026-07-23. Message-body logging is not enabled.

If policy disables Storage public network access, use an approved development
exception or add App Service VNet integration and a Storage private endpoint.
The sample does not bypass organizational policy.

## Exercise all approaches

```bash
./scripts/test-token-usage-e2e.sh \
  --simple-requests 3 \
  --parallel-requests 6 \
  --output /tmp/token-usage-result.json
```

The test creates an isolated APIM subscription through Azure Resource Manager,
deletes it on exit, applies sequential and concurrent model load, and verifies:

- APIM returns consumed and remaining token headers
- Log Analytics reports exactly the measured per-run simple-path usage
- The APIM-only usage policy returns subscription-scoped Log Analytics usage
- Concurrent strict reservations cannot exceed the configured quota
- The authoritative ledger equals successful response usage
- Some concurrent strict requests are rejected while reservations hold budget

The result contains aggregate counts only. It does not contain keys, prompts, or
model responses.

## API

All operations use the same `Ocp-Apim-Subscription-Key`.

| Operation | Purpose |
| --- | --- |
| `POST /token-usage/simple/chat/completions` | OpenAI-compatible nonstreaming chat through `llm-token-limit` |
| `GET /token-usage/simple/usage` | App Service current-month Log Analytics aggregation |
| `POST /token-usage/apim-only/chat/completions` | APIM-only nonstreaming chat through an independent `llm-token-limit` counter |
| `GET /token-usage/apim-only/usage` | APIM policy current-month Log Analytics aggregation |
| `POST /token-usage/strict/chat/completions` | Nonstreaming chat with atomic quota reservation |
| `GET /token-usage/strict/usage` | Current authoritative quota state and daily history |

APIM replaces any caller-provided subscription identity with
`context.Subscription.Id`. Consumers receive no Azure RBAC access.

## Semantics

The simple and APIM-only quotas reset at the UTC month boundary. Their remaining
headers are APIM estimates, and their usage endpoints reflect Azure Monitor
ingestion delay. The APIM-only usage policy uses fixed KQL and injects
`context.Subscription.Id`; callers cannot submit arbitrary KQL.

The strict endpoint reserves a conservative maximum before calling Foundry,
then replaces that reservation with reported actual usage in one table
transaction. Requests that cannot reserve the full amount are rejected. If a
request fails after it might have reached Foundry, or its reservation expires,
the full reservation is charged rather than silently undercounted. Streaming is
not supported. To keep the reservation bound auditable, the endpoint accepts
exactly one text message with role `user`.

Defaults are intentionally small for isolated testing:

| azd variable | Default |
| --- | ---: |
| `SIMPLE_TOKEN_QUOTA` | 600 |
| `STRICT_TOKEN_QUOTA` | 600 |
| `STRICT_RESERVATION_TOKENS` | 256 |
| `STRICT_MAX_OUTPUT_TOKENS` | 64 |
| `STRICT_SAFETY_PADDING_TOKENS` | 64 |

Increase the reservation when accepting larger prompts or output limits. The
serialized request size, output limit, and safety padding must fit inside one
reservation.

References:

- [`llm-token-limit`](https://learn.microsoft.com/azure/api-management/llm-token-limit-policy)
- [APIM LLM logging](https://learn.microsoft.com/azure/api-management/api-management-howto-llm-logs)
- [`llm-emit-token-metric`](https://learn.microsoft.com/azure/api-management/llm-emit-token-metric-policy)
