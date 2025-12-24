# Programmatically Creating Agents in Azure AI Foundry

This guide explains how to programmatically create AI agents in your Microsoft Foundry project after provisioning infrastructure with Bicep templates.

## Overview

Azure AI Foundry agents are intelligent assistants powered by large language models (LLMs) that can be configured with custom instructions, tools, and capabilities. While the Bicep templates provision the infrastructure (AI Services, Projects, Applications, and Deployments), the actual agent logic must be created separately.

This repository provides multiple approaches for programmatic agent creation:

1. **.NET SDK** - **Recommended** for application integration and Azure-native development
2. **Python SDK** - Alternative for Python-based workflows
3. **REST API with Bash/Azure CLI** - Best for CI/CD and automation
4. **REST API directly** - For custom implementations in any language

## Prerequisites

- Azure AI Foundry infrastructure deployed (see [azd-deployment.md](./azd-deployment.md))
- Azure CLI installed and authenticated: `az login`
- Model deployments available in your Azure OpenAI service or Azure AI Services

### For .NET SDK Approach (Recommended)

- .NET 9.0 or higher
- Azure CLI authenticated or appropriate Azure credentials

### For Python SDK Approach

- Python 3.8 or higher
- Install required packages:
  ```bash
  pip install -r scripts/python/requirements.txt
  ```

### For Bash Script Approach

- Bash shell (Linux, macOS, WSL, or Git Bash on Windows)
- `jq` (optional, for better JSON formatting)

## Quick Start

### Option 1: .NET SDK (Recommended)

The .NET SDK provides native Azure integration, strong typing, and comprehensive error handling.

```bash
# Set environment variables (from azd deployment)
eval $(azd env get-values)

# Navigate to the .NET project
cd scripts/dotnet/CreateAgent

# Create an agent
dotnet run
```

**Example with custom parameters:**

```bash
dotnet run -- \
  --model-id gpt-4o \
  --agent-name my-customer-service-agent \
  --agent-instructions "You are a customer service agent that helps users with product questions" \
  --agent-description "Customer service automation"
```

**Using in your .NET application:**

```csharp
using Azure.AI.Agents.Persistent;
using Azure.Identity;

// Authenticate and create client
var credential = new DefaultAzureCredential();
var projectEndpoint = Environment.GetEnvironmentVariable("COGNITIVE_SERVICES_ENDPOINT");
var agentsClient = new PersistentAgentsClient(projectEndpoint, credential);

// Create agent
var agent = await agentsClient.Administration.CreateAgentAsync(
    model: "gpt-4o",
    name: "my-agent",
    instructions: "You are a helpful assistant.",
    description: "My custom agent"
);

Console.WriteLine($"Created agent: {agent.Value.Id}");
```

### Option 2: Python SDK

The Python SDK is ideal for Python-based applications and workflows.

```bash
# Set environment variables (from azd deployment)
eval $(azd env get-values)

# Create an agent
python scripts/python/create-agent.py
```

**Example with custom parameters:**

```bash
python scripts/python/create-agent.py \
  --model-id gpt-4o \
  --agent-name my-customer-service-agent \
  --agent-instructions "You are a customer service agent that helps users with product questions" \
  --agent-description "Customer service automation"
```

**Using in your Python application:**

```python
import os
from azure.identity import DefaultAzureCredential
from azure.ai.projects import AIProjectClient

# Authenticate and create client
credential = DefaultAzureCredential()
project_client = AIProjectClient(
    endpoint=os.environ["PROJECT_ENDPOINT"],
    credential=credential
)

# Create agent
with project_client:
    agent = project_client.agents.create_agent(
        model=os.environ["MODEL_DEPLOYMENT_NAME"],
        name="my-agent",
        instructions="You are a helpful assistant.",
    )
    print(f"Created agent: {agent.id}")
```

> **Note:** The environment variable `PROJECT_ENDPOINT` should be in the format:
> `https://<foundry-resource-name>.services.ai.azure.com/api/projects/<project-name>`

### Option 3: Bash Script with REST API

The bash script is ideal for CI/CD pipelines and automation workflows.

```bash
# Set environment variables (from azd deployment)
eval $(azd env get-values)

# Create an agent
./scripts/create-agent.sh
```

**Example with custom parameters:**

```bash
./scripts/create-agent.sh \
  --model gpt-4-turbo \
  --name my-agent \
  --instructions "You are a specialized AI assistant" \
  --description "Production agent for customer inquiries"
```

### Option 4: Direct REST API

You can call the REST API directly from any programming language or tool.

**Endpoint Format:**

```
POST https://{foundry-resource-name}.services.ai.azure.com/api/projects/{project-name}/assistants?api-version=2025-05-01
```

> **Note:** The GA API version is `2025-05-01`. For preview features, use `2025-05-15-preview`.

**Authentication:**

```bash
# Get access token (use https://ai.azure.com as the resource)
ACCESS_TOKEN=$(az account get-access-token \
  --resource https://ai.azure.com \
  --query accessToken -o tsv)
```

**Request:**

```bash
curl -X POST "${AZURE_AI_FOUNDRY_PROJECT_ENDPOINT}/assistants?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o",
    "name": "my-agent",
    "description": "My custom agent",
    "instructions": "You are a helpful AI assistant.",
    "temperature": 0.7,
    "top_p": 0.95
  }'
```

## Agent Configuration Options

When creating an agent, you can configure various properties:

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `model` | string | Yes | Model deployment ID (e.g., "gpt-4o", "gpt-4-turbo") |
| `name` | string | No | Display name for the agent |
| `description` | string | No | Description of the agent's purpose |
| `instructions` | string | No | System instructions defining agent behavior |
| `temperature` | float | No | Sampling temperature (0-2, default: 1) |
| `top_p` | float | No | Nucleus sampling (0-1, default: 1) |
| `tools` | array | No | Array of tool definitions (Code Interpreter, File Search, etc.) |
| `tool_resources` | object | No | Resources for tools (file IDs, vector store IDs) |
| `metadata` | object | No | Custom key-value pairs (max 16) |
| `response_format` | string | No | Response format ("auto", "json_object", "text") |

### Available Tools

Microsoft Foundry agents support several built-in tools:

- **Code Interpreter**: Execute Python code
- **File Search**: Search through uploaded documents
- **Bing Grounding**: Web search capabilities
- **Function Calling**: Custom API integrations
- **Azure AI Search**: Enterprise search integration

**Example with tools:**

```python
agent = project_client.agents.create_agent(
    model="gpt-4o",
    name="research-agent",
    instructions="You are a research assistant that can search the web and analyze data.",
    tools=[
        {"type": "CodeInterpreter"},
        {"type": "BingGrounding"},
        {"type": "FileSearch"}
    ]
)
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy Agent

on:
  push:
    branches: [main]

jobs:
  deploy-agent:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Get Environment Variables
        run: |
          cd ${{ github.workspace }}
          azd env select production
          eval $(azd env get-values)
          echo "COGNITIVE_SERVICES_ENDPOINT=${COGNITIVE_SERVICES_ENDPOINT}" >> $GITHUB_ENV
          echo "PROJECT_NAME=${PROJECT_NAME}" >> $GITHUB_ENV
      
      - name: Create Agent
        run: |
          ./scripts/create-agent.sh \
            --model gpt-4o \
            --name production-agent \
            --instructions "$(cat agent-config/instructions.txt)"
```

### Azure DevOps Pipeline Example

```yaml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: AzureCLI@2
  displayName: 'Create Agent'
  inputs:
    azureSubscription: 'Azure-Service-Connection'
    scriptType: 'bash'
    scriptLocation: 'scriptPath'
    scriptPath: 'scripts/create-agent.sh'
    arguments: '--model gpt-4o --name production-agent'
```

## Testing Your Agent

After creating an agent, you can test it by creating a conversation thread:

**Python SDK:**

```python
# Create a thread
thread = project_client.agents.threads.create()

# Add a message
message = project_client.agents.messages.create(
    thread_id=thread.id,
    role="user",
    content="Hello! Can you help me?"
)

# Create and process the run (waits for completion)
run = project_client.agents.runs.create_and_process(
    thread_id=thread.id,
    agent_id=agent.id
)

# Check run status
if run.status == "failed":
    print(f"Run failed: {run.last_error}")

# Get messages from the thread
messages = project_client.agents.messages.list(thread_id=thread.id)
for message in messages:
    if message.text_messages:
        print(f"{message.role}: {message.text_messages[-1].text.value}")
```

**REST API:**

```bash
# Create thread
THREAD_RESPONSE=$(curl -X POST \
  "${AZURE_AI_FOUNDRY_PROJECT_ENDPOINT}/threads?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json")

THREAD_ID=$(echo "$THREAD_RESPONSE" | jq -r '.id')

# Add message
curl -X POST \
  "${AZURE_AI_FOUNDRY_PROJECT_ENDPOINT}/threads/${THREAD_ID}/messages?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "role": "user",
    "content": "Hello! Can you help me?"
  }'

# Run the agent
curl -X POST \
  "${AZURE_AI_FOUNDRY_PROJECT_ENDPOINT}/threads/${THREAD_ID}/runs?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"assistant_id": "'${AGENT_ID}'"}'
```

## Publishing Agents to Applications

Once you've created and tested an agent, you can publish it to an application for external access:

1. **Via Azure Portal:**
   - Navigate to your Foundry project
   - Select the agent
   - Click "Publish" and follow the wizard

2. **Via REST API:**
   ```bash
   # Update the agent deployment with agent reference
   curl -X PATCH \
     "${ENDPOINT}/api/projects/${PROJECT_NAME}/applications/${APPLICATION_NAME}/agentDeployments/${DEPLOYMENT_NAME}?api-version=2025-10-01-preview" \
     -H "Authorization: Bearer ${ACCESS_TOKEN}" \
     -H "Content-Type: application/json" \
     -d '{
       "agents": [{
         "agentName": "my-agent",
         "agentVersion": "1"
       }]
     }'
   ```

## Troubleshooting

### Common Issues

**1. "Failed to obtain access token"**
- Ensure you're logged in: `az login`
- Verify you have access to the subscription: `az account show`

**2. "Model not found" or "Invalid model ID"**
- Check available models in your AI Services: `az cognitiveservices account deployment list`
- Ensure the model is deployed and available in your region

**3. "Forbidden" or "Unauthorized"**
- Verify you have the correct role assignments (Cognitive Services User or Contributor)
- Check that the AI Services account has `allowProjectManagement: true`

**4. "Project not found"**
- Verify the project exists: `az cognitiveservices account show`
- Check the project name matches: `azd env get-values`

**5. Python SDK Import Errors**
- Install the correct packages: `pip install azure-ai-projects azure-identity`
- Ensure Python version is 3.8 or higher: `python --version`

### Enable Debug Logging

**Python:**
```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

**Bash:**
```bash
# Add -v flag to curl commands
curl -v -X POST ...
```

**Azure CLI:**
```bash
az config set core.only_show_errors=false
az config set logging.enable_log_file=true
```

## Best Practices

1. **Version Control:** Store agent configurations in version control
2. **Environment Variables:** Use environment variables for credentials and endpoints
3. **Idempotency:** Check if an agent exists before creating to avoid duplicates
4. **Error Handling:** Implement proper error handling and retry logic
5. **Monitoring:** Use Azure Monitor to track agent usage and performance
6. **Security:** Never hardcode credentials; use managed identities when possible
7. **Testing:** Test agents thoroughly before deploying to production
8. **Documentation:** Document your agent's purpose, instructions, and expected behavior

## Additional Resources

- [Azure AI Foundry Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Azure AI Agent Service REST API Reference](https://learn.microsoft.com/en-us/rest/api/aifoundry/aiagents/)
- [Azure AI Projects SDK for Python](https://pypi.org/project/azure-ai-projects/)
- [Azure CLI Documentation](https://learn.microsoft.com/en-us/cli/azure/)
- [Azure Developer CLI (azd) Documentation](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/)
- [Main Deployment Guide](./azd-deployment.md)

## Limitations and Considerations

- The Azure AI Agent Service GA API version is `2025-05-01`; preview version is `2025-05-15-preview`
- Use the preview API for tools that are in preview
- Some features may have regional availability restrictions
- Rate limits apply based on your Azure AI Services SKU
- Agent deployments require the infrastructure provisioned via Bicep (see main.bicep)
- Model deployments must be created separately (either via Azure Portal or additional Bicep configuration)

## Support and Contributing

For issues, questions, or contributions, please refer to the main repository README.

## Documentation Test History

### 2025-12-22
- Result: PASS with fixes
- Platform/Context: Microsoft Surface Laptop, Windows local development
- OS: Windows 11 Enterprise (build 10.0.26200)
- Shell: PowerShell 7.5.4 (Core)
- Tester: Automated Documentation Tester
- Notes:
  - **Critical fixes applied:**
    1. Updated Python SDK code to use `AIProjectClient(endpoint=..., credential=...)` instead of deprecated `from_connection_string()` method
    2. Removed invalid import `from azure.ai.projects.models import Agent` (class no longer exists in SDK v2.0.0b2)
    3. Updated REST API version from `2025-10-01-preview` to GA version `2025-05-01`
    4. Changed token resource from `https://cognitiveservices.azure.com` to `https://ai.azure.com`
    5. Updated environment variable names to match current SDK (`PROJECT_ENDPOINT` instead of `COGNITIVE_SERVICES_ENDPOINT`)
    6. Updated agent testing code to use current SDK patterns (`threads.create()`, `messages.create()`, `runs.create_and_process()`)
  - **Prerequisites verified:** Azure CLI 2.63.0, Python 3.12.10, azd 1.22.5, azure-ai-projects 2.0.0b2
  - **Blocking issue:** No model deployments exist in the test environment (Bicep `enableAgentDeployments` defaults to `false`)
  - **Manual intervention required:** Actual agent creation could not be tested end-to-end without deploying a model
