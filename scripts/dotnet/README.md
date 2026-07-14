# .NET tools

This directory contains small .NET console applications for Microsoft Foundry automation.

## Tools

| Tool | Purpose |
| --- | --- |
| `CreateAgent` | Programmatically create prompt-agent versions in Microsoft Foundry. |
| `FoundryGuideFeedback` | Call the optional Foundry Guide agent and emit a trace-correlated `foundry_guide.feedback` custom event to Application Insights. |

## Agent creation

## Requirements

- .NET 10 or higher
- Azure CLI authenticated (`az login`) or appropriate Azure credentials
- Microsoft Foundry project endpoint

## Quick Start

```bash
# Navigate to the CreateAgent directory
cd scripts/dotnet/CreateAgent

# Load environment variables from azd deployment
eval $(azd env get-values --cwd ../../..)

# Run the application
dotnet run
```

## Usage

```bash
# Using environment variables
dotnet run

# With custom parameters
dotnet run -- --model-id gpt-5.4 --agent-name my-agent

# Show help
dotnet run -- --help
```

## Build and Publish

```bash
# Build the project
dotnet build

# Publish as self-contained executable
dotnet publish -c Release -r linux-x64 --self-contained

# Run published executable
./bin/Release/net9.0/linux-x64/publish/CreateAgent --help
```

## NuGet Packages

- `Azure.AI.Projects` (2.0.1) - Azure AI Projects client library
- `Azure.AI.Projects.Agents` (2.0.0) - agent administration APIs
- `Azure.Identity` (1.21.0) - Azure authentication library

## Documentation

See [docs/agent-creation.md](../../../docs/agent-creation.md) for comprehensive documentation and examples.
