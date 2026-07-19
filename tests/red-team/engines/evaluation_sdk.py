from __future__ import annotations

import tempfile
from pathlib import Path
from typing import Any, Awaitable, Callable

from azure.ai.evaluation.red_team import AttackStrategy, RedTeam, RiskCategory
from azure.core.credentials import TokenCredential

from campaigns.config import CampaignError, EngineConfig


class EngineResultError(RuntimeError):
    pass


class EvaluationSdkEngine:
    def __init__(
        self,
        *,
        project_endpoint: str,
        credential: TokenCredential,
        config: EngineConfig,
        application_scenario: str,
    ) -> None:
        self._project_endpoint = project_endpoint
        self._credential = credential
        self._config = config
        self._application_scenario = application_scenario

    async def run(
        self,
        target: Callable[..., Awaitable[dict[str, Any]]],
        *,
        scan_name: str,
    ) -> dict[str, Any]:
        risk_categories = _map_values(
            self._config.risk_categories,
            RiskCategory,
            "risk category",
        )
        attack_strategies = _map_values(
            self._config.attack_strategies,
            AttackStrategy,
            "attack strategy",
        )

        with tempfile.TemporaryDirectory(prefix="foundry-red-team-") as output_dir:
            raw_output = Path(output_dir) / "raw-scan.json"
            red_team = RedTeam(
                azure_ai_project=self._project_endpoint,
                credential=self._credential,
                risk_categories=risk_categories,
                num_objectives=self._config.num_objectives,
                application_scenario=self._application_scenario,
                output_dir=output_dir,
            )
            result = await red_team.scan(
                target=target,
                scan_name=scan_name,
                attack_strategies=attack_strategies,
                skip_upload=True,
                output_path=raw_output,
                parallel_execution=self._config.parallel_execution,
                timeout=self._config.timeout_seconds,
            )
            scorecard = result.to_scorecard()

        if not isinstance(scorecard, dict):
            raise EngineResultError("Evaluation SDK returned no scorecard.")
        return scorecard


def _map_values(
    configured_values: tuple[str, ...],
    enum_type: type,
    description: str,
) -> list:
    available = {item.value: item for item in enum_type}
    values = []
    for configured_value in configured_values:
        value = available.get(configured_value)
        if value is None:
            raise CampaignError(
                f"Unsupported {description}: {configured_value}."
            )
        values.append(value)
    return values
