# .NET Tools for Microsoft Foundry

This directory contains .NET console applications for working with Microsoft Foundry.

## Tools

| Tool | Description |
|------|-------------|
| [CreateAgent](./CreateAgent/) | Create an AI agent in Microsoft Foundry |
| [VerifyStreamingCachedTokens](./VerifyStreamingCachedTokens/) | Verify `cached_tokens` in streaming Chat Completions usage chunks |

## Requirements

- .NET 10 or higher
- Azure CLI authenticated (`az login`) or appropriate Azure credentials
- Microsoft Foundry infrastructure deployed (see [azd-deployment.md](../../docs/azd-deployment.md))

## CreateAgent

Create an AI agent in Microsoft Foundry using the .NET SDK.

```bash
cd scripts/dotnet/CreateAgent
eval $(azd env get-values --cwd ../../..)
dotnet run
```

See [docs/agent-creation.md](../../docs/agent-creation.md) for details.

## VerifyStreamingCachedTokens

Verify that `cached_tokens` is returned in streaming Chat Completions usage chunks when using `stream_options: {"include_usage": true}`.

```bash
cd scripts/dotnet/VerifyStreamingCachedTokens
eval $(azd env get-values --cwd ../../..)
dotnet run -- --deployment gpt-5.2
```

See [docs/streaming-cached-tokens.md](../../docs/streaming-cached-tokens.md) for details.
