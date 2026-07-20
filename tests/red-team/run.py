from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

from azure.identity import AzureCliCredential

from campaigns.config import CampaignError, TargetConfig, load_campaign
from engines.pyrit_engine import PyritEngine, initialize_pyrit_memory
from results.summary import campaign_verdict, invalid_summary, summarize_attacks
from targets.foundry_prompt_agent import (
    FoundryModelTarget,
    FoundryPromptAgentTarget,
)


ROOT = Path(__file__).resolve().parent
DEFAULT_CAMPAIGN = ROOT / "campaigns" / "foundry-guide-smoke.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a local, sanitized red-team campaign."
    )
    parser.add_argument(
        "--campaign",
        type=Path,
        default=DEFAULT_CAMPAIGN,
        help="Campaign JSON path.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional path for the sanitized JSON summary.",
    )
    return parser.parse_args()


async def run(args: argparse.Namespace) -> int:
    campaign = load_campaign(args.campaign)
    if campaign.engine.type != "pyrit":
        raise CampaignError(f"Unsupported engine: {campaign.engine.type}.")

    project_endpoint = required_environment("PROJECT_ENDPOINT").rstrip("/")
    model_name = required_environment("MODEL_DEPLOYMENT_NAME")
    credential = AzureCliCredential()
    memory = initialize_pyrit_memory()
    judge_target = FoundryModelTarget(
        project_endpoint=project_endpoint,
        model_name=model_name,
        credential=credential,
    )
    engine = PyritEngine(
        judge_target=judge_target,
        config=campaign.engine,
        objective=campaign.objective,
        policy=campaign.policy,
        memory=memory,
    )

    target_results = []
    try:
        for target_config in campaign.targets:
            started = time.monotonic()
            target_name = resolved_target_name(target_config)
            try:
                target = create_target(
                    target_config,
                    target_name=target_name,
                    project_endpoint=project_endpoint,
                    credential=credential,
                )
                executions = await engine.run(target)
                target_results.append(
                    summarize_attacks(
                        executions,
                        target_type=target_config.type,
                        target_name=target_config.name,
                        duration_seconds=time.monotonic() - started,
                    )
                )
            except Exception as error:
                print(
                    f"Target '{target_config.name}' produced an invalid run: "
                    f"{type(error).__name__}.",
                    file=sys.stderr,
                )
                target_results.append(
                    invalid_summary(
                        target_type=target_config.type,
                        target_name=target_config.name,
                        error_type=type(error).__name__,
                        duration_seconds=time.monotonic() - started,
                    )
                )
    finally:
        engine.close()

    summary: dict[str, Any] = {
        "schemaVersion": 1,
        "campaign": campaign.name,
        "engine": campaign.engine.type,
        "verdict": campaign_verdict(target_results),
        "targets": target_results,
    }
    rendered = json.dumps(summary, indent=2, sort_keys=True)
    print(rendered)

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(f"{rendered}\n", encoding="utf-8")

    return {"pass": 0, "fail": 1, "invalid": 2}[summary["verdict"]]


def create_target(
    config: TargetConfig,
    *,
    target_name: str,
    project_endpoint: str,
    credential: AzureCliCredential,
) -> FoundryPromptAgentTarget:
    if config.type != "foundry-prompt-agent":
        raise CampaignError(f"Unsupported target: {config.type}.")
    return FoundryPromptAgentTarget(
        project_endpoint=project_endpoint,
        agent_name=target_name,
        credential=credential,
    )


def resolved_target_name(config: TargetConfig) -> str:
    if config.type == "foundry-prompt-agent" and config.name == "foundry-guide":
        return os.environ.get("FOUNDRY_GUIDE_AGENT_NAME", config.name)
    return config.name


def required_environment(name: str) -> str:
    value = os.environ.get(name)
    if value is None or not value.strip():
        raise CampaignError(f"{name} is required.")
    return value.strip()


def main() -> int:
    args = parse_args()
    try:
        return asyncio.run(run(args))
    except CampaignError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
