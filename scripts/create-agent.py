#!/usr/bin/env python3
"""
Create an AI agent in Azure AI Foundry using the Azure AI Agent Service SDK.

This script demonstrates how to programmatically create an agent in a Microsoft Foundry
project that has been provisioned with Bicep templates.

Prerequisites:
- Azure CLI installed and authenticated (az login)
- Python 3.8 or higher
- Azure AI Agent Service SDK: pip install azure-ai-projects azure-identity

Usage:
    # Using environment variables from azd
    python create-agent.py

    # Or specify parameters explicitly
    python create-agent.py --project-endpoint <endpoint> --model-id <model>

Environment Variables (from 'azd env get-values'):
    COGNITIVE_SERVICES_ENDPOINT: Azure AI Services endpoint URL
    PROJECT_NAME: Name of the Foundry project
"""

import argparse
import os
import sys
from typing import Optional

try:
    from azure.identity import DefaultAzureCredential
    from azure.ai.projects import AIProjectClient
    from azure.ai.projects.models import Agent
except ImportError:
    print("Error: Required Azure SDK packages not found.")
    print("Please install them with: pip install azure-ai-projects azure-identity")
    sys.exit(1)


def get_project_endpoint() -> str:
    """Get the project endpoint from environment or construct it."""
    endpoint = os.getenv("COGNITIVE_SERVICES_ENDPOINT")
    if not endpoint:
        raise ValueError(
            "COGNITIVE_SERVICES_ENDPOINT environment variable not found. "
            "Run 'azd env get-values' or set it manually."
        )
    return endpoint


def create_agent(
    project_endpoint: str,
    model_id: str = "gpt-4o",
    agent_name: str = "foundry-agent",
    agent_instructions: str = "You are a helpful AI assistant.",
    agent_description: str = "Agent created programmatically via SDK",
) -> Agent:
    """
    Create an AI agent in Azure AI Foundry.

    Args:
        project_endpoint: Azure AI Services endpoint URL
        model_id: Model deployment ID (e.g., 'gpt-4o', 'gpt-4-turbo')
        agent_name: Name for the agent
        agent_instructions: System instructions for the agent
        agent_description: Description of the agent

    Returns:
        Agent: The created agent object

    Raises:
        Exception: If agent creation fails
    """
    print(f"Creating agent '{agent_name}' in project...")
    print(f"  Endpoint: {project_endpoint}")
    print(f"  Model: {model_id}")

    # Authenticate using DefaultAzureCredential
    # This supports multiple authentication methods:
    # - Environment variables
    # - Managed Identity
    # - Azure CLI (az login)
    # - Azure PowerShell
    # - Interactive browser
    credential = DefaultAzureCredential()

    # Create project client
    project_client = AIProjectClient.from_connection_string(
        conn_str=project_endpoint,
        credential=credential
    )

    # Create agent
    agent = project_client.agents.create_agent(
        model=model_id,
        name=agent_name,
        instructions=agent_instructions,
        description=agent_description,
    )

    print(f"✓ Agent created successfully!")
    print(f"  Agent ID: {agent.id}")
    print(f"  Agent Name: {agent.name}")
    print(f"  Model: {agent.model}")

    return agent


def main():
    parser = argparse.ArgumentParser(
        description="Create an AI agent in Azure AI Foundry",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Use environment variables from azd
  python create-agent.py

  # Specify custom parameters
  python create-agent.py --model-id gpt-4-turbo --agent-name my-assistant

  # Full customization
  python create-agent.py \\
    --project-endpoint https://cog-abc123.services.ai.azure.com \\
    --model-id gpt-4o \\
    --agent-name custom-agent \\
    --agent-instructions "You are a specialized customer service agent" \\
    --agent-description "Customer service automation agent"
        """,
    )

    parser.add_argument(
        "--project-endpoint",
        help="Azure AI Services endpoint (default: from COGNITIVE_SERVICES_ENDPOINT env var)",
    )
    parser.add_argument(
        "--model-id",
        default="gpt-4o",
        help="Model deployment ID (default: gpt-4o)",
    )
    parser.add_argument(
        "--agent-name",
        default="foundry-agent",
        help="Name for the agent (default: foundry-agent)",
    )
    parser.add_argument(
        "--agent-instructions",
        default="You are a helpful AI assistant.",
        help="System instructions for the agent",
    )
    parser.add_argument(
        "--agent-description",
        default="Agent created programmatically via SDK",
        help="Description of the agent",
    )

    args = parser.parse_args()

    try:
        # Get project endpoint
        project_endpoint = args.project_endpoint or get_project_endpoint()

        # Create agent
        agent = create_agent(
            project_endpoint=project_endpoint,
            model_id=args.model_id,
            agent_name=args.agent_name,
            agent_instructions=args.agent_instructions,
            agent_description=args.agent_description,
        )

        print("\n" + "=" * 60)
        print("Agent creation completed successfully!")
        print("=" * 60)
        print("\nNext steps:")
        print("  1. View your agent in Azure AI Foundry portal")
        print("  2. Test the agent with a conversation thread")
        print("  3. Publish the agent to an application for external access")
        print("\nFor more information, see docs/agent-creation.md")

    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
