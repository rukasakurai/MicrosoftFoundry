# Workload assumptions for cost estimates

Purpose: identify the workload inputs required before Microsoft Foundry cost
estimates become meaningful. If the user cannot provide an input, state the missing
assumption instead of inventing a number.

## Core rule

Separate:

- repo-known facts: resources, SKUs, defaults, toggles, model deployment settings,
  region;
- user-provided assumptions: volume, frequency, data size, retention, concurrency;
- pricing-source facts: dated meter prices, calculator output, Cost Management
  actuals;
- unknowns: inputs that must remain blank or be expressed as scenarios.

Never silently convert an unknown into a number.

## Assumptions to clarify or state

### Model usage

- model family / deployment type;
- standard token-based vs PTU / provisioned capacity;
- expected requests per day or month;
- average input tokens per request;
- average output tokens per request;
- expected peak concurrency or throughput requirement;
- evaluation / red-team run volume.

### Foundry IQ / Azure AI Search

- whether Foundry IQ is enabled;
- Search SKU, replicas, and partitions;
- number and approximate size of knowledge sources;
- initial indexing volume;
- re-index / refresh cadence;
- expected retrieval calls per day or month;
- average retrieved chunks or documents per request;
- chunking / embedding assumptions;
- whether indexes are split by tenant, product, environment, sensitivity, or other
  boundary;
- whether permission / label synchronization changes re-indexing frequency.

### Agents and tools

- expected agent sessions or runs;
- average tool calls per run;
- retry behavior;
- fan-out behavior;
- scheduled or background runs;
- hosted compute or memory usage;
- remote tools, gateways, or external paid APIs.

### Observability and operations

- telemetry GB per day or month;
- log retention period;
- Application Insights / Log Analytics workspace assumptions;
- alerting or dashboard query frequency.

### Safety, governance, and admin-plane surfaces

- guardrails / Content Safety usage volume;
- Purview / DSPM enablement;
- Defender for Cloud plan state;
- Entra premium / governance dependency;
- API Management or gateway use;
- budgets, quotas, or Azure Policy constraints.

## Scenario handling

If the user does not know workload volume, offer a small scenario set instead of a
fake estimate:

- idle / provisioned only;
- light usage;
- expected usage;
- stress / upper-bound usage.

Each scenario must clearly list its assumptions.

## Output rule

Every estimate should include:

- region;
- currency;
- date/time;
- pricing source;
- repo-known facts used;
- user-provided assumptions used;
- missing assumptions;
- whether the number is estimate, scenario, or actual cost.
