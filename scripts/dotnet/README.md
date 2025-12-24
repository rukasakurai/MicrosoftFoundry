# .NET Agent Creation Tool

This directory contains a .NET console application for programmatically creating AI agents in Azure AI Foundry.

## Requirements

- .NET 9.0 or higher
- Azure CLI authenticated (`az login`) or appropriate Azure credentials
- Azure AI Foundry project endpoint

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
dotnet run -- --model-id gpt-4o --agent-name my-agent

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

- `Azure.AI.Agents.Persistent` (1.2.0-beta.8) - Azure AI Persistent Agents client library
- `Azure.Identity` (1.17.1) - Azure authentication library

## Documentation

See [docs/agent-creation.md](../../../docs/agent-creation.md) for comprehensive documentation and examples.
