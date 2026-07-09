# AI Red Teaming Agent boundary notes

The AI Red Teaming Agent is a Microsoft Foundry evaluation capability for probing
and scoring generative AI systems. It is **not** itself a Foundry Agent Service
agent.

## Roles

| Role | Meaning |
| --- | --- |
| Caller | Starts the eval run. This can be a local script, CI job, Azure Container App, or other automation. |
| AI Red Teaming Agent | Foundry-managed red-team service that generates adversarial test items and runs the eval workflow. |
| Target | The model or Foundry agent being tested. |
| Evaluator / testing criteria | Built-in scorers such as prohibited actions, sensitive data leakage, and task adherence. |

## What is easy to misread

- A prompt agent can be a **target**, but it cannot act as the caller because it
  cannot run arbitrary code to call eval APIs.
- A Hosted Agent or Azure Container App can act as the **caller**, but that does
  not mean the built-in evaluator/scoring service runs there.
- The cloud REST path uses `/openai/evals`, but that path alone does not prove
  the target or evaluator model provider.
- Public docs list both prompt agents and hosted/container agents as supported
  targets. Validate the exact Hosted Agent shape before assuming it will produce
  scored output.

## Data-plane REST API

AI Red Teaming Agent artifacts used by the cloud run flow are data-plane eval
resources under the Foundry project endpoint; no matching control-plane / ARM
resource type was found as of 2026-07-09 JST.

The official cloud run how-to shows examples using this project endpoint shape:

```text
https://<account>.services.ai.azure.com/api/projects/<project>
```

Could not find a dedicated REST API reference page for these Microsoft Foundry
project-scoped red-team endpoints as of 2026-07-09 JST. The official source
found is the how-to page,
[Run AI Red Teaming Agent in the cloud](https://learn.microsoft.com/azure/foundry/how-to/develop/run-ai-red-teaming-cloud),
which includes cURL examples for these paths:

| Artifact | REST API |
| --- | --- |
| Eval group | `POST /openai/evals`; `GET /openai/evals/{eval_id}` |
| Eval run | `POST /openai/evals/{eval_id}/runs`; `GET /openai/evals/{eval_id}/runs/{run_id}` |
| Output items | `GET /openai/evals/{eval_id}/runs/{run_id}/output_items` |
| Taxonomy | `PUT /evaluationtaxonomies/{name}` |

## Portal URL patterns

Observed in the live Foundry portal on 2026-07-09 JST. The project route prefix
has the form:

```text
https://ai.azure.com/nextgen/r/{project-route}
```

Red-team evaluation pages use these paths:

| Page | Portal path |
| --- | --- |
| All evaluations | `/build/evaluations/list` |
| Evaluator catalog | `/build/evaluations/catalog` |
| Red team list | `/build/evaluations/redteam` |
| Create red-team run | `/build/evaluations/redteam/create` |
| Red-team eval group | `/build/evaluations/redteam/{eval_id}` |
| Red-team run details | `/build/evaluations/redteam/{eval_id}/run/{run_id}` |

The general evaluations list can also link to eval groups and runs without the
`/redteam` segment. The portal redirects red-team run detail pages to the
`/build/evaluations/redteam/{eval_id}/run/{run_id}` form.

## Cost note

The public docs do not make the AI Red Teaming Agent cost model self-evident.
Treat red-team runs as potentially spanning multiple cost surfaces:

- target model tokens,
- Foundry evaluator/system model usage,
- Hosted Agent compute if used as caller or target,
- Azure Container Apps / ACR if used as caller,
- Application Insights / Log Analytics telemetry.

Use Azure Cost Management after running tests; do not infer actual spend from
the eval configuration alone.
