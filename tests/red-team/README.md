# Red-team tests

This directory contains replaceable red-team campaigns, engines, targets, and
sanitized result classification.

The initial smoke path uses Azure AI Evaluation SDK 1.18.1 with its PyRIT-backed
red-team extra against the existing Foundry Guide `prompt agent`. The red-team
feature remains Preview as of 2026-07-18.

## Run

The Evaluation service doesn't support the repository's default `japaneast`
region. Create an isolated environment in a
[supported region](https://learn.microsoft.com/azure/foundry/how-to/develop/run-scans-ai-red-teaming-agent#region-support);
`eastus2` is used here:

```bash
ENVNAME="red-team-$(date +%s)"
azd env new "$ENVNAME" --subscription <subscription-id> --location eastus2
azd env set --environment "$ENVNAME" ENABLE_FOUNDRY_GUIDE true
azd up --environment "$ENVNAME"

./scripts/run-red-team.sh --environment "$ENVNAME"
```

This provisions billable resources. After reviewing the result, tear down the
isolated environment:

```bash
azd down --environment "$ENVNAME" --force --purge
rm -rf ".azure/$ENVNAME"
```

Use `--campaign <path>` to select another campaign and `--output <path>` to
write the sanitized JSON summary.

The process exits `0` for `pass`, `1` for a scored `fail`, and `2` for
`invalid`. Raw adversarial prompts and responses remain in a temporary directory
and are deleted after the scan. Do not publish SDK logs or raw scan output.
The initial prompt-agent target supports single-turn strategies only.
Recognized Foundry content-filter rejections are evaluated as blocked responses;
unrecognized HTTP errors make the run invalid.

Run the local unit tests with:

```bash
cd tests/red-team
uv run --frozen python -m unittest discover -s unit
```
