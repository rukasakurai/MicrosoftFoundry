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
from engines.evaluation_sdk import EvaluationSdkEngine
from results.summary import campaign_verdict, invalid_summary, summarize_scorecard
from targets.foundry_prompt_agent import FoundryPromptAgentTarget


ROOT = Path(__file__).resolve().parent
DEFAULT_CAMPAIGN = ROOT / "campaigns" / "foundry-guide-smoke.json"
SUPPORTED_EVALUATION_REGIONS = {
    "eastus2",
    "francecentral",
    "northcentralus",
    "swedencentral",
    "switzerlandwest",
}
MULTI_TURN_STRATEGIES = {
    "crescendo",
    "multi_turn",
}


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
    if campaign.engine.type != "evaluation-sdk":
        raise CampaignError(f"Unsupported engine: {campaign.engine.type}.")

    project_endpoint = required_environment("PROJECT_ENDPOINT").rstrip("/")
    location = required_environment("AZURE_LOCATION").replace(" ", "").lower()
    if location not in SUPPORTED_EVALUATION_REGIONS:
        supported_regions = ", ".join(sorted(SUPPORTED_EVALUATION_REGIONS))
        raise CampaignError(
            f"Evaluation SDK red teaming is unavailable in region '{location}'. "
            f"Use an isolated azd environment in one of: {supported_regions}; "
            "pass it to scripts/run-red-team.sh with --environment <name>."
        )

    credential = AzureCliCredential()
    engine = EvaluationSdkEngine(
        project_endpoint=project_endpoint,
        credential=credential,
        config=campaign.engine,
        application_scenario=campaign.application_scenario,
    )

    target_results = []
    for target_config in campaign.targets:
        started = time.monotonic()
        target_name = resolved_target_name(target_config)
        try:
            validate_target_compatibility(
                target_config,
                campaign.engine.attack_strategies,
            )
            target = create_target(
                target_config,
                target_name=target_name,
                project_endpoint=project_endpoint,
                credential=credential,
            )
            scorecard = await engine.run(
                target,
                scan_name=f"{campaign.name}-{target_name}",
            )
            target_results.append(
                summarize_scorecard(
                    scorecard,
                    target_type=target_config.type,
                    target_name=target_name,
                    risk_categories=campaign.engine.risk_categories,
                    duration_seconds=time.monotonic() - started,
                )
            )
        except Exception as error:
            print(
                f"Target '{target_name}' produced an invalid run: "
                f"{type(error).__name__}.",
                file=sys.stderr,
            )
            target_results.append(
                invalid_summary(
                    target_type=target_config.type,
                    target_name=target_name,
                    error_type=type(error).__name__,
                    duration_seconds=time.monotonic() - started,
                )
            )

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


def validate_target_compatibility(
    config: TargetConfig,
    attack_strategies: tuple[str, ...],
) -> None:
    if config.type != "foundry-prompt-agent":
        return

    unsupported = sorted(MULTI_TURN_STRATEGIES.intersection(attack_strategies))
    if unsupported:
        raise CampaignError(
            "The Foundry prompt-agent callback is single-turn and does not support: "
            f"{', '.join(unsupported)}."
        )


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
