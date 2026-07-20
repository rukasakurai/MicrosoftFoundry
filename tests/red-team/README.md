# Red-team tests

This directory contains replaceable red-team campaigns, engines, targets, and
sanitized result classification.

## Threat model

Common tutorial harms such as violence are not priority threats for this repo.
The main concerns are the maintained deployment being repurposed to enable
attacks and a fork or derivative using the repository as an attack platform.
Runtime tests address the former; safe defaults and avoiding turnkey offensive
features reduce the latter.

## Design decisions

### Target

The maintained deployment is the primary threat-model scope. The repository's
`red-teaming` Agent Skill uses Copilot and Playwright MCP for adaptive testing of
user-reachable browser and API behavior.

The bounded PyRIT campaign targets the `prompt agent` to isolate generative
behavior; it does not claim end-to-end deployment coverage. A web-API PyRIT target
was evaluated, but the API's delegated `access_as_user` token is browser-bound and
Azure CLI cannot acquire it without changing the authentication design.

### Execution mechanism

Start with one policy and two single-turn attacks. The current implementation
uses PyRIT 0.14.0 for a direct request and bundled jailbreak, then uses the
environment's model deployment to judge each response against the binary policy.

Red-team campaigns remain manual; when a fixed finding can be minimized into a
public-safe, repeatable case, promote only that case to routine security
regression testing.

The Agent Skill complements PyRIT with adaptive, human-attested exploration at the
cost of model-dependent behavior and AI-credit consumption.

As of 2026-07-20, the Azure AI Evaluation SDK's managed red-team path adds
generic risk categories and regional service dependencies, while the
`AI Red Teaming Agent` adds cloud-run lifecycle overhead and isn't available in
Japan East.
Keep direct PyRIT unless scheduled or larger campaigns, durable shared evidence,
or tool-aware agentic evaluation becomes necessary; availability alone isn't a
reason to switch.

## Run

Use a provisioned azd environment with `ENABLE_FOUNDRY_GUIDE=true`:

```bash
./scripts/run-red-team.sh
```

Use `--environment <name>` to avoid changing the globally selected environment.
Use `--output <path>` to write the sanitized JSON summary.

The process exits `0` for `pass`, `1` for a scored `fail`, and `2` for
`invalid`. PyRIT's local cache is in memory, but prompts and responses are sent
to the selected Azure target and judge and follow those services' data-handling
behavior. Console output can contain adversarial content, so do not publish it.

Run the local unit tests with:

```bash
cd tests/red-team
uv run --frozen python -m unittest discover -s unit
```
