# Verifying Streaming Usage with Cached Tokens

This guide explains how to verify that `cached_tokens` is returned in streaming Chat Completions usage chunks when using `stream_options: {"include_usage": true}` on Microsoft Foundry.

## Background

[Prompt caching](https://learn.microsoft.com/en-us/azure/foundry/openai/latest#openaichatcompletionstreamoptions) allows the API to reuse previously processed prompt prefixes, reducing latency and cost for repeated requests. When streaming is enabled with `stream_options: {"include_usage": true}`, the API returns a final usage chunk (before `[DONE]`) that includes token consumption details.

The [`CompletionUsagePromptTokensDetails`](https://learn.microsoft.com/en-us/azure/foundry/openai/latest#openaicompletionusageprompttokensdetails) schema includes a `cached_tokens` field that reports how many prompt tokens were served from cache.

### Requirements for prompt caching

- The prompt must be **at least 1,024 tokens** long
- The **first 1,024+ tokens** must be **identical** between requests for a cache hit
- A GPT-5.2 or later model deployment is recommended

## Quick Start

### Bash Script

```bash
# Load environment variables from azd
eval $(azd env get-values)

# Run verification with your model deployment
./scripts/verify-streaming-cached-tokens.sh --deployment gpt-5.2
```

### .NET Console App

```bash
cd scripts/dotnet/VerifyStreamingCachedTokens

# Load environment variables from azd
eval $(azd env get-values --cwd ../../..)

# Run verification
dotnet run -- --deployment gpt-5.2
```

## What the Verification Does

Both scripts perform the same steps:

1. **Generate a long prompt** (≥ 1,024 tokens) using repeated deterministic text
2. **Send the first streaming request** with `stream_options: {"include_usage": true}`
3. **Wait briefly** for the cache to be established
4. **Send the same request again** to trigger a cache hit
5. **Inspect the final usage chunk** from each response

## Expected Results

### First Request (No Cache)

The final SSE chunk's `usage` object should show `cached_tokens: 0`:

```json
{
  "prompt_tokens": 1500,
  "completion_tokens": 50,
  "total_tokens": 1550,
  "prompt_tokens_details": {
    "cached_tokens": 0
  }
}
```

### Second Request (Cache Hit)

The final SSE chunk's `usage` object should show `cached_tokens > 0`:

```json
{
  "prompt_tokens": 1500,
  "completion_tokens": 50,
  "total_tokens": 1550,
  "prompt_tokens_details": {
    "cached_tokens": 1408
  }
}
```

> **Note**: The `cached_tokens` value is rounded to the nearest cache boundary (typically multiples of 128 tokens).

## Acceptance Criteria

| Criterion | Expected |
|-----------|----------|
| First request: `cached_tokens` | `0` (no cache yet) |
| Second request: `cached_tokens` | `> 0` (cache hit) |
| Both requests: `prompt_tokens` | Populated (not null) |
| Both requests: `completion_tokens` | Populated (not null) |
| Both requests: `prompt_tokens_details` | Present |

## SSE Streaming Format

When `stream: true` and `stream_options: {"include_usage": true}` are set, the response is a series of server-sent events (SSE). The final chunk before `data: [DONE]` contains the usage information:

```
data: {"id":"...","choices":[],"usage":{"prompt_tokens":1500,"completion_tokens":50,"total_tokens":1550,"prompt_tokens_details":{"cached_tokens":0}}}

data: [DONE]
```

> **Note**: In the usage chunk, the `choices` array is empty. All content chunks have `usage: null`.

## Script Options

### Bash Script

```
Usage: verify-streaming-cached-tokens.sh [OPTIONS]

Options:
  --endpoint <url>         Azure AI Services endpoint
                           (default: from COGNITIVE_SERVICES_ENDPOINT env var)
  --deployment <name>      Model deployment name (required, e.g., gpt-5.2)
  --api-version <version>  API version (default: 2025-04-01-preview)
  --help                   Show help message
```

### .NET Console App

```
Usage: VerifyStreamingCachedTokens [OPTIONS]

Options:
  --endpoint, -e <url>       Azure AI Services endpoint
                             (default: from COGNITIVE_SERVICES_ENDPOINT env var)
  --deployment, -d <name>    Model deployment name (required, e.g., gpt-5.2)
  --help, -h                 Show help message
```

## Related Documentation

- [Azure Developer CLI Deployment](./azd-deployment.md)
- [Agent Creation](./agent-creation.md)
