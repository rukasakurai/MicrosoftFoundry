#!/usr/bin/env python3
"""
Create an AI agent in Microsoft Foundry using the Azure AI Agent Service SDK.

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
    PROJECT_ENDPOINT: Microsoft Foundry project endpoint URL
        Format: https://<foundry-resource>.services.ai.azure.com/api/projects/<project-name>
    MODEL_DEPLOYMENT_NAME: Name of the model deployment to use (e.g., 'gpt-4o')
"""

import argparse
import os
import sys
from typing import Optional

try:
    from azure.identity import DefaultAzureCredential
    from azure.ai.projects import AIProjectClient
except ImportError:
    print("Error: Required Azure SDK packages not found.")
    print("Please install them with: pip install azure-ai-projects azure-identity")
    sys.exit(1)


def get_project_endpoint() -> str:
    """Get the project endpoint from environment.
    
    The endpoint should be in format:
    https://<foundry-resource>.services.ai.azure.com/api/projects/<project-name>
    """
    # Try new environment variable first, fall back to legacy
    endpoint = os.getenv("PROJECT_ENDPOINT") or os.getenv("COGNITIVE_SERVICES_ENDPOINT")
    project_name = os.getenv("PROJECT_NAME")
    
    if not endpoint:
        raise ValueError(
            "PROJECT_ENDPOINT environment variable not found. "
            "Run 'eval $(azd env get-values)' or set it manually. "
            "Format: https://<resource>.services.ai.azure.com/api/projects/<project>"
        )
    
    # If endpoint doesn't include /api/projects/, construct full endpoint
    if "/api/projects/" not in endpoint and project_name:
        endpoint = f"{endpoint.rstrip('/')}/api/projects/{project_name}"
    
    return endpoint


def get_model_deployment_name() -> str:
    """Get model deployment name from environment."""
    model = os.getenv("MODEL_DEPLOYMENT_NAME")
    if not model:
        # Default to gpt-4o if not specified
        return "gpt-4o"
    return model


def create_agent(
    project_endpoint: str,
    model_id: str = "gpt-4o",
    agent_name: str = "foundry-agent",
    agent_instructions: str = "You are a helpful AI assistant.",
):
    """
    Create an AI agent in Microsoft Foundry.

    Args:
        project_endpoint: Microsoft Foundry project endpoint URL
        model_id: Model deployment ID (e.g., 'gpt-4o', 'gpt-4-turbo')
        agent_name: Name for the agent
        agent_instructions: System instructions for the agent

    Returns:
        The created agent object

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

    # Create project client with the new SDK pattern
    project_client = AIProjectClient(
        endpoint=project_endpoint,
        credential=credential
    )

    # Create agent using context manager
    with project_client:
        agent = project_client.agents.create_agent(
            model=model_id,
            name=agent_name,
            instructions=agent_instructions,
        )

        print(f"✓ Agent created successfully!")
        print(f"  Agent ID: {agent.id}")
        print(f"  Agent Name: {agent.name}")

        return agent


def main():
    parser = argparse.ArgumentParser(
        description="Create an AI agent in Microsoft Foundry",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Use environment variables from azd
  python create-agent.py

  # Specify custom parameters
  python create-agent.py --model-id gpt-4-turbo --agent-name my-assistant

  # Full customization
  python create-agent.py \\
    --project-endpoint https://<resource>.services.ai.azure.com/api/projects/<project> \\
    --model-id gpt-4o \\
    --agent-name custom-agent \\
    --agent-instructions "You are a specialized customer service agent"
        """,
    )

    parser.add_argument(
        "--project-endpoint",
        help="Microsoft Foundry project endpoint (default: from PROJECT_ENDPOINT env var)",
    )
    parser.add_argument(
        "--model-id",
        default=None,
        help="Model deployment ID (default: from MODEL_DEPLOYMENT_NAME env var or 'gpt-4o')",
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

    args = parser.parse_args()

    try:
        # Get project endpoint
        project_endpoint = args.project_endpoint or get_project_endpoint()
        
        # Get model deployment name
        model_id = args.model_id or get_model_deployment_name()

        # Create agent
        agent = create_agent(
            project_endpoint=project_endpoint,
            model_id=model_id,
            agent_name=args.agent_name,
            agent_instructions=args.agent_instructions,
        )

        print("\n" + "=" * 60)
        print("Agent creation completed successfully!")
        print("=" * 60)
        print("\nNext steps:")
        print("  1. View your agent in Microsoft Foundry portal")
        print("  2. Test the agent with a conversation thread")
        print("  3. Publish the agent to an application for external access")
        print("\nFor more information, see docs/agent-creation.md")

    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
