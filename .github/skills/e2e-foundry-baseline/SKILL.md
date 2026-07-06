---
name: e2e-foundry-baseline
description: Run an end-to-end (E2E) test of this repo's Microsoft Foundry baseline before merging to main — provision an isolated azd environment, verify the model deploys and serves a response and that an agent can be created, then tear it down. Use when validating an infra/, scripts/, or agent-flow change against the E2E-before-merge policy, or when deciding how much regression to run for a PR.
---

# E2E-testing the Microsoft Foundry baseline

## When to Use

- A PR touches `infra/`, `scripts/`, or a documented agent flow and must satisfy the
  **E2E-testing-before-merge** expectation (see `AGENTS.md` → Development & Deployment).
- You need to decide *how much* to test for a given PR (regression scope is a
  per-PR judgment call).
- You need a repeatable, isolated way to prove the baseline actually runs — not just
  that Bicep compiles.

This skill assumes the **Microsoft Foundry resource** architecture
(`Microsoft.CognitiveServices/accounts`, kind `AIServices`) provisioned by this repo.

## Testable surfaces, feasibility, and reference times

Pick the smallest set that covers the changed behavior; escalate to more of the list
only when the change warrants it.

The **time** column is a single-run reference (one subscription, `japaneast`/`eastus2`,
default params) — indicative, not a guarantee. Provisioning dominates; everything after
provisioning is seconds. Status reflects what was actually observed when this table was
grounded.

Budget the **fixed overhead** any provisioning flow carries, on top of the per-flow
time below: `azd provision` ~**2.5 min** and, at the end, `azd down --force --purge`
~**3 min** (observed 2m48s–3m07s). So a clean provision→test→teardown cycle is
~**6 min minimum** even for a 2-second data-plane check. Batch multiple data-plane
flows into one provisioned environment rather than paying that overhead per flow.

**Regression budget (wall clock, incl. teardown).** Total time is driven by how many
provision→teardown cycles you run, not by summing the rows — the data-plane flows
(2, 3, 4, 6, 10) share **one** provisioned env (~40s combined after provision):

- **Core happy-path** (provision → flows 2, 3, 4, 6, 10 → teardown): ~**6–7 min**.
- **Full regression**: ~**20–25 min** — the core cycle plus separate provision→teardown
  cycles for flow 7 (toggle, fails) and flow 12 (region), flow 5 (.NET, local, ~10s)
  and flow 9 (OIDC, CI, ~20–60s); flow 11 isn't runnable without OAuth credentials.

These are **machine/Azure wall-clock only**, assuming you're already authenticated,
consent is already granted, every flow passes first try, and no result interpretation.
Real elapsed effort is **higher and partly unbounded**, because a run also incurs:

- **Owner consent** before provisioning (a human round-trip — minutes to hours of
  waiting, not compute).
- **One-time interactive auth** when `az`/`azd` aren't signed in (device-code browser
  login).
- **Portal / Playwright flows** (8, 10 registry view, 11) — multi-step navigate →
  snapshot → review, realistically **minutes each**, not the API-call seconds listed.
- **Result interpretation** per flow, and **failure investigation** when something
  deviates (re-runs, root-causing) — unbounded by nature.

Treat the minute figures as a **floor**, not an ETA.

| # | Flow | E2E check | Time | Status / notes |
| --- | --- | --- | --- | --- |
| 1 | Baseline provision (`azd up` → account + project + model) | provision succeeds; outputs populated | ~150s | ✅ easy |
| 2 | Model serves inference | `POST {PROJECT_ENDPOINT}/openai/v1/responses` → 200 + reply | ~2s | ✅ easy |
| 3 | Agent creation (Bash) `scripts/create-agent.sh` | agent created, 2xx, versioned | ~15s | ✅ easy |
| 4 | Agent run step (documented flow) | run → 200 | ~2s | ✅ old `…/responses?api-version=` returns 404; use `/openai/v1/responses` |
| 5 | Agent creation (.NET) `scripts/dotnet/CreateAgent` | `dotnet run` → agent created | ~10s to fail | ❌ sample does not compile (SDK type drift) — [known bug #35](https://github.com/rukasakurai/MicrosoftFoundry/issues/35) |
| 6 | MCP agent (Responses API MCP tool) | create + run; `mcp_call` in output | ~15s | ✅ easy with an auth-free MCP; `scripts/create-mcp-agent.sh` itself needs a connection (flow 11) |
| 7 | `enableAgentDeployments=true` path | provision with the toggle on | ~180s to fail | ❌ fails: `Agents cannot be null or empty` — [known bug #34](https://github.com/rukasakurai/MicrosoftFoundry/issues/34); supplying `agents:[…]` via ARM does **not** fix it |
| 8 | Agent publish → application/deployment update | agent deployed to an application | ~50s (ARM attempt) | ⚠️ ARM path fails (same as flow 7, [#34](https://github.com/rukasakurai/MicrosoftFoundry/issues/34)); the **portal Publish** action works — use it (Playwright) |
| 9 | Azure OIDC (`.github/workflows/azure-oidc-check.yml`) | federated GitHub Actions login | ~20–60s (runner queue) | ⚠️ triggers via `gh workflow run`; green needs an Entra federated-identity credential matching the branch ref (`AADSTS700213` otherwise) |
| 10 | Entra agent identity / registry | `instance_identity` present; agent visible in portal | ~5s | ✅ identity auto-created (agent API); agent also visible in the nextgen portal project view (Playwright) |
| 11 | MCP OAuth connection `scripts/create-mcp-agent.sh` | project connection + consent flow | — | ⚠️ heavy: needs a real OAuth app (client id/secret). Portal "Connect a tool → MCP" dialog exists (Playwright); a working OAuth connection can't be created without those credentials |
| 12 | Region / SKU / model / capacity overrides | provision with non-default params | ~170s | ✅ easy (per param combination). `enableObservability=false` is a variation here — it drops the observability resources, ≈ the pre-observability baseline |
| 13 | Observability + agent-run tracing (`enableObservability`, default on) | App Insights connection attached; after a run, spans land in the Log Analytics workspace | ~+18s provision, then ~2–3 min ingestion lag | ✅ resolves #36. Verify deterministically by querying the workspace (see below), not the portal |

Flows 8, 9, and 11 are setup-dependent and don't fit an automated per-PR E2E;
validate them out-of-band and note that in the PR. For portal-based checks (agent
visible in the project, MCP connection dialog, Publish action), the
`foundry-ui-playwright` skill can drive an authenticated portal session — verified to
work without an interactive login when the operator already has a portal session in
the target tenant.

**Flow 13 — deterministic tracing check.** After provisioning (observability on) and
running an agent, confirm span-level telemetry actually landed. Query the **Log
Analytics workspace** (workspace-based App Insights routes telemetry there; the
App-Insights-by-appId query API may be blocked by a proxy — see the environment
gotcha). Allow ~2–3 min for ingestion, then look for an `invoke_agent` span:

```bash
RG="rg-$ENVNAME"
WSID=$(az monitor log-analytics workspace show -g "$RG" \
  -n "$LOG_ANALYTICS_WORKSPACE_NAME" --query customerId -o tsv | tr -d '\r\n')
az monitor log-analytics query -w "$WSID" \
  --analytics-query "AppDependencies | where TimeGenerated > ago(20m) | project Name, DependencyType" -o table
# green = an "invoke_agent <name>:<version>" row (plus a "chat <model>" span) is present
```

> **Keeping this table honest:** the Status column is a grounded observation, not a
> spec. Linked issues (e.g. [#34](https://github.com/rukasakurai/MicrosoftFoundry/issues/34),
> [#35](https://github.com/rukasakurai/MicrosoftFoundry/issues/35)) are the source of
> truth for the ❌/⚠️ rows. **If you fix a linked bug or change a flow's behavior,
> update the matching row here in the same PR** (and close/reference the issue).

### Time the timed operations — deviations are a signal

Whenever you run a flow that has a reference time here (or the provision/teardown
overhead), **actually measure it** (e.g. wrap it in `t=$SECONDS; …; echo $((SECONDS-t))s`)
and compare to the number above. The reference times are a cheap regression signal:

- **Small deviation (within ~2×):** normal run-to-run variance (region, load, cold
  start). Ignore.
- **Large deviation (roughly ≥3× slower, or an operation that used to be seconds now
  taking minutes):** treat as a symptom that something may be wrong — a service-side
  regression, a changed API surface, retries masking an error, or a config problem.
  Re-run once to rule out a transient blip.
- **Repeated or logically-explainable large deviation:** if a large deviation
  reproduces across runs, or you can point to a concrete cause (e.g. a new retry
  loop, an added synchronous wait, a slower API version), **file a GitHub issue**
  with the flow number, the reference vs. observed time, how many runs you saw it
  across, and any suspected cause. Update the reference time here only once the new
  timing is confirmed as the correct steady state (not a symptom of the bug).

**Environment gotcha:** in some environments a proxy rejects long management-plane
REST URLs (nested `accounts/.../projects/.../applications?...`) with `HTTP 400
Invalid URL`, while short URLs, ARM template deployments, and data-plane
(`*.services.ai.azure.com`) calls succeed. Prefer `azd`/ARM deployments or the
portal over direct `az rest` for nested management resources.

## Prerequisites and the auth gotcha

- `az` and `azd` installed; the operator signed in to `az` against the target
  subscription's tenant.
- **`azd` may be signed in to a different identity/tenant than `az`.** If `azd up`
  fails with a principal/tenant resolution error, or an `AADSTS50076` MFA error for
  Azure Resource Manager, make `azd` reuse the `az` CLI's (MFA-satisfied) token:

  ```bash
  azd config set auth.useAzCliAuth true
  ```

  `azd`'s own device-code login often does **not** satisfy an MFA conditional-access
  policy for ARM; the `az` CLI token does. Revert with
  `azd config unset auth.useAzCliAuth` when finished.

## Procedure (isolated throwaway environment)

> **Cost & consent:** this provisions **real, billable** Azure resources. Get the
> repo owner's go-ahead before running, always use an **isolated throwaway env**
> (never a persistent/shared one), and tear down afterward (next section).

Run from the repo root on the branch under test. Use a unique env name so the run is
isolated from any persistent environment.

```bash
# 1. Isolate: new azd env (does not touch existing environments)
ENVNAME="e2e-$(date +%s | tail -c 6)"
azd env new "$ENVNAME" --subscription <subscription-id> --location <region>

# 2. Auth bridge (see gotcha above), then provision
azd config set auth.useAzCliAuth true
azd provision --no-prompt        # expect the model deployment to show as Done

# 3. Load outputs and exercise the flow
set -a; eval "$(azd env get-values)"; set +a
./scripts/create-agent.sh --name e2e-agent          # expect: created, 2xx

# 4. Prove the model actually serves a response (path-versioned by /v1; no api-version)
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)
curl -s -w '\nHTTP %{http_code}\n' \
  -X POST "${PROJECT_ENDPOINT}/openai/v1/responses" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"model":"'"$MODEL_DEPLOYMENT_NAME"'","input":"Reply with exactly: E2E_OK"}'
```

A run is **green** when: provision succeeds, the model deployment is created, the
agent is created (2xx), and the run returns HTTP 200 with the expected text.

## Teardown and state restore (always)

Teardown is not instant: `azd down --force --purge` takes ~**3 min** (observed
2m48s–3m07s) because it deletes the resource group and purges the soft-deleted
Cognitive Services account. Wait for it to finish before considering the run done.

```bash
azd down --force --purge                     # delete + purge the throwaway resources (~3 min)
azd env select <your-default-env>            # restore the previous default env
rm -rf ".azure/$ENVNAME"                      # remove the local throwaway env
azd config unset auth.useAzCliAuth           # revert the auth config change
```

Leave the workspace exactly as found: no leftover resource groups, azd envs, or
config changes.

## Gotchas worth knowing

- **Model quota / lifecycle.** New frontier models can ship with **0 default quota**,
  so `azd up` fails at validation until quota is granted. Prefer a **GA** model with
  existing quota as the default. Check with
  `az cognitiveservices usage list --location <region>` and lifecycle via the
  [Models API](https://learn.microsoft.com/rest/api/aiservices/accountmanagement/models).
  A *Deprecating* model is blocked for **new** subscriptions, which breaks the
  clean-`azd up` story for fresh users.
- **Run endpoint.** The current run surface is `POST {PROJECT_ENDPOINT}/openai/v1/responses`
  (versioned by `/v1`, no `?api-version`). Older `.../responses?api-version=...` paths
  can return 404.
- **Provision creates the resource group before validating**, so a validation failure
  can still leave an empty RG — delete it during teardown.
- **Trailing `\r` from `az` output.** On Windows/WSL, `az ... -o tsv` can emit values
  with a trailing carriage return. Piped into a resource id or ARM parameter, it
  corrupts the path (e.g. `ParentResourceNotFound`). Strip it: `... -o tsv | tr -d '\r\n'`.

## Public-safe / secret hygiene

- Never write access tokens, subscription/tenant IDs, or endpoints into committed
  files or PR comments. Use placeholders (`<subscription-id>`, `<region>`).
- Report evidence as status + HTTP codes + a short model reply, not raw credentials.
