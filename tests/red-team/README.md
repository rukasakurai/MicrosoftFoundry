# Red-team tests

This directory contains replaceable red-team campaigns, engines, targets, and
sanitized result classification.

The initial campaign uses PyRIT 0.14.0 against the existing Foundry Guide
`prompt agent`. It tests one threat: whether a direct request or bundled
single-turn jailbreak can turn the scoped guide into a source of actionable
assistance for an unauthorized attack. A separate call to the environment's model
deployment judges each response against that binary policy.

## Run

Use a provisioned azd environment with `ENABLE_FOUNDRY_GUIDE=true`:

```bash
./scripts/run-red-team.sh
```

Use `--environment <name>` to avoid changing the globally selected environment.
Use `--output <path>` to write the sanitized JSON summary.

The process exits `0` for `pass`, `1` for a scored `fail`, and `2` for
`invalid`. Raw attack prompts and target responses remain only in PyRIT's
in-memory store. Console output can still contain adversarial content, so do not
publish it.

Run the local unit tests with:

```bash
cd tests/red-team
uv run --frozen python -m unittest discover -s unit
```
