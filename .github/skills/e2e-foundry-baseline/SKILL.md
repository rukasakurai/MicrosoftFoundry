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

## Testable surfaces and feasibility

Pick the smallest set that covers the changed behavior; escalate to more of the list
only when the change warrants it.

| Flow | E2E check | Ease |
| --- | --- | --- |
| Baseline provision (`azd up` → account + project + model) | provision succeeds; outputs populated | easy |
| Model serves inference | `POST {PROJECT_ENDPOINT}/openai/v1/responses` → 200 + reply | easy |
| Agent creation (Bash) `scripts/create-agent.sh` | agent created, 2xx, versioned | easy |
| Agent run step (documented flow) | run → 200 | easy |
| Agent creation (.NET) `scripts/dotnet/CreateAgent` | `dotnet run` → agent created | needs .NET SDK |
| `enableAgentDeployments=true` path | provision with the toggle on | easy (param variation) |
| MCP agent `scripts/create-mcp-agent.sh` | approval / OAuth item detection | needs an MCP server + OAuth |
| Region / SKU / model / capacity overrides | provision with non-default params | easy but combinatorial |
| Azure OIDC (`docs/azure-oidc-setup.md`, `.github/workflows/`) | federated GitHub Actions login | CI-only, needs repo secrets |
| Entra agent identity / registry, MCP OAuth connection | agent identity / consent flows | mostly manual / tenant-admin |

The last two rows are largely manual and don't fit an automated per-PR E2E; validate
them out-of-band and note that in the PR.

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

```bash
azd down --force --purge                     # delete + purge the throwaway resources
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

## Public-safe / secret hygiene

- Never write access tokens, subscription/tenant IDs, or endpoints into committed
  files or PR comments. Use placeholders (`<subscription-id>`, `<region>`).
- Report evidence as status + HTTP codes + a short model reply, not raw credentials.
