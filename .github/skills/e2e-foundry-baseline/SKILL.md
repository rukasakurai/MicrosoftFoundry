---
name: e2e-foundry-baseline
description: Run end-to-end (E2E) verification of this repo's Microsoft Foundry baseline and its documentation/runbooks (README + docs/) before merging to main — provision an isolated azd environment, verify the model deploys and serves a response and that an agent can be created, walk each doc's runnable steps (including browser/GUI steps via Playwright MCP) and confirm the docs aren't stale, then tear it down. Use when validating an infra/, scripts/, docs/, or agent-flow change against the E2E-before-merge policy, or when deciding how much regression to run for a PR.
---

# E2E verification of the Microsoft Foundry baseline

## When to Use

- A PR touches `infra/`, `scripts/`, or a documented agent flow and must satisfy the
  **E2E-before-merge** expectation (see `AGENTS.md` → Development & Deployment).
- A PR touches `README.md` or `docs/` and you need to confirm the documented steps
  actually work when followed and that the docs aren't **stale**. Historically a human
  ran the runbook; Copilot can now execute it too — including GUI steps, via Playwright
  MCP (see the coverage map below).
- You need to decide *how much* to verify for a given PR (regression scope is a
  per-PR judgment call).
- You need a repeatable, isolated way to prove the baseline actually runs — not just
  that Bicep compiles.

This skill covers two kinds of verification: **executing** the baseline and its
runbooks (run it, observe the result), and **checking documents against reality**
(does the markdown still match the live portal/API/Learn — i.e. is it stale). Both
must stay concrete: a verification is only a PASS if you *observed* the result — see
"blocked ≠ pass" below.

This skill assumes the **Microsoft Foundry resource** architecture
(`Microsoft.CognitiveServices/accounts`, kind `AIServices`) provisioned by this repo.

## Agent Skills coverage

Treat Agent Skills under `.github/skills/` as part of the repo baseline: they are
reusable runbooks whose metadata, links, and referenced resources should stay valid.
When a PR changes a skill, verify that skill directly and use adjacent skills instead
of duplicating their guidance:

- `foundry-ui-playwright` — portal navigation, live UI checks, screenshots, and
  reference notes under `foundry-ui-playwright/references/` (including Azure Pricing
  Calculator navigation).
- `foundry-cost` — cost impact checks, pricing-meter mapping, Azure Pricing
  Calculator caveats, and Cost Management `ActualCost` observations.
The operator may also have adjacent user-scoped skills installed. Use them when
available, but don't treat them as repo-baseline files unless they exist under
`.github/skills/`.

For a skills-only PR, use a lightweight skills verification pass instead of a clean
`azd up` unless the changed skill affects provisioning/runtime behavior:

- skill metadata, relative links, and whitespace: ~0s;
- external pricing/Learn/OWASP reference URLs: ~36s;
- Retail Prices API example queries: ~2s;
- public Azure Pricing Calculator page with Playwright: ~19s.

## Verifiable surfaces, feasibility, and reference times

Pick the smallest set that covers the changed behavior; escalate to more of the list
only when the change warrants it.

The **time** column is a single-run reference (one subscription, `japaneast`/`eastus2`,
default params) — indicative, not a guarantee. Provisioning dominates; everything after
provisioning is seconds. Status reflects what was actually observed when this table was
grounded.

Budget the **fixed overhead** any provisioning flow carries, on top of the per-flow
time below: `azd provision` ~**2.5 min** and, at the end, `azd down --force --purge`
~**3 min** (observed 2m48s–3m07s). So a clean provision→verify→teardown cycle is
~**6 min minimum** even for a 2-second data-plane check. Batch multiple data-plane
flows into one provisioned environment rather than paying that overhead per flow.

**Keeping Foundry IQ E2E fast (`enableFoundryIq=true`).** The `~2.5 min` provision
figure above is the *fast* case; with Foundry IQ the provision includes an **Azure AI
Search service whose allocation time is highly variable — observed 6s to ~13 min on the
`basic` SKU in the same region**. That variance is Azure-side allocation, not a hang, so:

- **Reuse a warm env for data-plane iteration.** The Search allocation is paid once.
  Most Foundry IQ iteration is on the *scripts* (`scripts/foundry-iq-setup.sh`,
  `scripts/create-foundry-iq-agent.sh`) and data-plane objects, not Bicep — re-run
  those against an already-provisioned env (seconds). Do a clean `azd up` only when
  `infra/` changes or as the final pre-merge gate.
- **Keep Search at `basic`.** Basic is the *minimum* tier that supports agentic
  retrieval (Free doesn't), and it's sufficient for this baseline, so a higher tier
  (Standard) only adds cost with no benefit here. (Whether a higher tier allocates any
  faster or slower was not measured — only `basic` was used — so don't bump the SKU
  expecting a speed change either way.)
- **Drop what you're not testing.** `enableFoundryIq` is off by default, so the
  standard baseline never pays this cost; likewise set `enableObservability=false` when
  observability isn't under test (drops the Log Analytics + App Insights resources,
  each ~20-25s to provision — though they run in parallel and Search usually dominates
  the critical path, so the wall-clock saving is often small).
- **A slow Search create is variance, not failure.** Don't abort a run that's still
  provisioning Search; region-hopping is a last resort only (it adds a variable).

**Regression budget (wall clock, incl. teardown).** Total time is driven by how many
provision→teardown cycles you run, not by summing the rows — the data-plane flows
(2, 3, 4, 6, 10) share **one** provisioned env (~40s combined after provision):

- **Core happy-path** (provision → flows 2, 3, 4, 6, 10 → teardown): ~**6–7 min**.
- **Full regression**: ~**20–25 min** — the core cycle plus a separate provision→teardown
  cycle for flow 12 (region), plus flow 5 (.NET, local, ~10s) and flow 9 (OIDC, CI,
  ~20–60s); flow 7 is a ~5s static check (no provisioning), and flow 11 isn't runnable
  without OAuth credentials.

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
| 5 | Agent creation (.NET) `scripts/dotnet/CreateAgent` | `dotnet run` → agent created | ~17s (warm; first run adds restore+build) | ✅ builds and creates an agent. Uses `AzureCliCredential` (not `DefaultAzureCredential`, which stalls ~3 min probing IMDS locally). Pins stable `Azure.AI.Projects` 2.0.1 / `Azure.AI.Projects.Agents` 2.0.0 |
| 6 | MCP agent + evidence-safe validation (`scripts/verify-agent-run.sh`) | create + run; return a **pass/fail/invalid** verdict from the output items (not just prose). `mcp_call` with output → `pass`; message-only → `invalid` | ~15s | ✅ easy with an auth-free MCP. `pass` + `invalid` are testable here; the `fail`/consent branch needs an OAuth connection (flow 11). `create-mcp-agent.sh` runs it automatically |
| 7 | `enableAgentDeployments` toggle removed (#34) | compiled ARM has no `enableAgentDeployments` param and no `applications`/`agentDeployments` resources (`az bicep build` + `jq`) | ~5s | ✅ resolves #34: the toggle always failed (`Agents cannot be null or empty`) because agents are data-plane only (created via `/agents`, flows 3/5) and published via portal/REST (flow 8) — it was removed rather than fixed |
| 8 | Agent publish → application/deployment | agent published to an application | ~50s | ⚠️ not an ARM/Bicep path; use **portal Publish** (Playwright) or the publish REST API — publishing auto-creates the application + deployment |
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

## Documentation coverage (README + docs/)

Each doc below maps to one or more flows above (or a docs-accuracy check); the **How an
AI verifies a doc** runbook after the table says how, and results go in that doc's own
**Documentation Test History**.

The **content-verify time** is the wall-clock for a *content staleness pass* (links,
API-version currency, and claim accuracy vs the repo and Microsoft Learn) — **not** a
full runnable pass (that adds the ~6 min provision→teardown). Each is a single-run
reference from a `general-purpose` subagent on a **fixed model** (`claude-sonnet-4.5`,
self-timed) — the fixed model is what keeps them roughly repeatable. Treat as a floor;
GUI/Playwright and live provisioning are extra.

> **Each time is tied to the doc's content at the moment it was measured — it goes stale
> the instant that doc changes.** So whenever you edit a doc in this table (in any PR),
> the old number no longer applies: **re-run the timed content pass** (same fixed-model,
> self-timed subagent) **and update that row in the same change.** Never cite an existing
> row's time for a doc you just edited without re-measuring — that's how a stale figure
> ships. (If you edit the doc but not its verification surface, still re-measure; link
> and claim counts drive the time.)

| Doc | Covered by | Content-verify time | AI-verifiable now? |
| --- | --- | --- | --- |
| `README.md` (setup order + "What This Is") | link/claims check, then the linked docs below | ~55s | ✅ every setup-order link resolves, the order runs, and the claims ("runnable out of the box", observability) match flows 1 / 2 / 13 |
| `docs/azd-deployment.md` | flows 1, 2, 12, 13 | ~15s | ✅ |
| `docs/agent-creation.md` | flows 3, 4, 5, 6, 8 | ~30s | ✅ (flow 8 publish: REST is scriptable; the portal path uses Playwright) |
| `docs/azure-oidc-setup.md` | flow 9 | ~30s | ⚠️ needs an Entra federated-identity credential set up out-of-band |
| `docs/entra-agent-identity.md` | flow 10 | ~30s | ⚠️ *create* needs the **Agent ID Administrator** role + admin consent; read/list is verifiable |
| `docs/entra-agent-registry.md` | flow 10 | ~30s | ❌ **registration retired 2026-06-15**: `POST /beta/agentRegistry/agentInstances` returns `503` ("use the Microsoft Agent 365 registration API"), though `GET` still returns `200` — the doc's core register flow is broken and it's stale until rewritten |
| `docs/agent-mcp-oauth.md` | flow 11 | ~35s | ⚠️ needs a real OAuth app (client id/secret) |
| `docs/operate/data-security-governance.md` | docs-accuracy check (no provisioning flow) | ~15s | ✅ verify the claims against Microsoft Learn + the live portal pane with Playwright; it's a **preview** feature, so confirm the caveats still hold and date the result |
| `docs/operate/policies.md` | docs-accuracy check (no provisioning flow) | ~65s + portal check | ✅ verify claims against Microsoft Learn, the live **Operate → Compliance → Policies** portal (Preview badge + **Create policy** page footer and scope choices) with Playwright, and `az policy set-definition show` / `az policy definition show` (guardrail initiative/defs are `[Preview]`, `Audit`-only and inspect `raiPolicy` configuration, not runtime prompts/responses); if verifying scan results, expect async delay (**No scan results** initially; tens of minutes, possibly up to 24h) and use detached/background logging rather than an in-turn polling loop; **preview**, so confirm caveats still hold and date the result |
| `docs/operate/guardrails.md` | docs-accuracy check (no provisioning flow) | ~31s + portal check | ✅ verify claims against Microsoft Learn plus the live **Build → Guardrails** create/assignment flow and **Operate → Compliance → Guardrails** matrix with Playwright; confirm the Compliance view remains read-only and links remediation back to Build; **preview**, so confirm caveats still hold and date the result |
| `docs/foundry-iq.md` | docs-accuracy check (no provisioning flow; the API/trace claims need a Foundry IQ env, `enableFoundryIq=true`) | ~85s | ✅ verify claims vs Microsoft Learn (GA/preview split, document-level access, MCP per-user limits); **partly preview**, so confirm the caveats still hold and date the result |
| `docs/owasp-genai-risk-control-mapping/README.md` | docs-accuracy check (no provisioning flow): caveats, internal consistency with deep dives, table integrity, Known unknowns safety guidance | ~14s | ✅ verify this as working analysis: source/link freshness, internal consistency, and overclaim review — not proof that every risk assignment is objectively correct; Known unknowns must stay scoped to public/sanitized validation |
| `docs/owasp-genai-risk-control-mapping/api-center.md` | docs-accuracy check (no provisioning flow): Microsoft Learn links + design-time/runtime boundary claims | ~28s | ✅ verify links and the boundary that API Center is design-time inventory/governance, not runtime enforcement, vulnerability scanning, model provenance, or identity enforcement |
| `docs/owasp-genai-risk-control-mapping/entra.md` | docs-accuracy check (no provisioning flow): Microsoft Learn links + identity/control-boundary claims | ~31s | ✅ verify links and the boundary that Entra owns identity/authorization/lifecycle, not content safety, data classification, runtime traffic, vulnerability/provenance scanning, or transport security |

## How an AI verifies a doc (runbook)

1. **Read the whole doc first**, then run the steps in order in an isolated env
   (reuse the provisioned baseline for data-plane docs; see the procedure below).
2. **Execute every runnable step**, including GUI ones — drive the portal with
   Playwright MCP (`foundry-ui-playwright`), don't just assert the docs *say* to click.
3. **Fix small drift in place** (stale API version, renamed portal label, wrong
   endpoint) as part of the verification, exactly as the historical human testers did.
4. **Append a dated entry** to that doc's *Documentation Test History* (PASS / PASS
   with fixes / FAIL + what changed). Keep it **public-safe**: status + HTTP codes +
   short replies, never tokens, subscription/tenant IDs, or endpoints.
5. **Blocked ≠ pass.** If a step needs a credential/role/consent you don't have, mark
   that step ⚠️ and say what's required — don't record a PASS you didn't observe.

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

Teardown is slow (~**3 min**: `azd down --force --purge` deletes the resource group
and purges the soft-deleted Cognitive Services account — and the Log Analytics
workspace, if observability was on). **Don't block on it.** Once the run is green,
the *verdict is already known*, so start teardown in the **background** and use the
wait to do useful work (commit, open/update the PR, write the summary):

```bash
# Kick off teardown detached; capture its log so you can confirm success later.
nohup azd down --force --purge > /tmp/azd-down-$ENVNAME.log 2>&1 &
# ... now continue with commit / PR / reporting while Azure deletes ...
```

Then, **before merging**, confirm teardown actually finished cleanly (a teardown
failure — e.g. a purge that needs a fix — is merge-relevant, so it must be checked,
just not blocked on):

```bash
grep -E 'SUCCESS|ERROR' /tmp/azd-down-$ENVNAME.log   # expect SUCCESS, no ERROR
azd env select <your-default-env>            # restore the previous default env
rm -rf ".azure/$ENVNAME"                      # remove the local throwaway env
azd config unset auth.useAzCliAuth           # revert the auth config change
```

If you must run teardown synchronously (e.g. no background support), it still takes
~3 min; wait for `SUCCESS` before considering the run done. Either way, leave the
workspace exactly as found: no leftover resource groups, azd envs, or config changes.

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
