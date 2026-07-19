from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class CampaignError(ValueError):
    pass


@dataclass(frozen=True)
class EngineConfig:
    type: str
    risk_categories: tuple[str, ...]
    attack_strategies: tuple[str, ...]
    num_objectives: int
    timeout_seconds: int
    parallel_execution: bool


@dataclass(frozen=True)
class TargetConfig:
    type: str
    name: str


@dataclass(frozen=True)
class Campaign:
    name: str
    application_scenario: str
    engine: EngineConfig
    targets: tuple[TargetConfig, ...]


def load_campaign(path: Path) -> Campaign:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CampaignError(f"Unable to read campaign: {path}") from error

    if not isinstance(data, dict) or data.get("schemaVersion") != 1:
        raise CampaignError("Campaign schemaVersion must be 1.")

    name = _required_string(data, "name")
    application_scenario = _required_string(data, "applicationScenario")

    engine_data = _required_object(data, "engine")
    engine_type = _required_string(engine_data, "type")
    risk_categories = _required_string_list(engine_data, "riskCategories")
    attack_strategies = _required_string_list(engine_data, "attackStrategies")
    num_objectives = _positive_integer(engine_data, "numObjectives")
    timeout_seconds = _positive_integer(engine_data, "timeoutSeconds")
    parallel_execution = engine_data.get("parallelExecution")
    if not isinstance(parallel_execution, bool):
        raise CampaignError("engine.parallelExecution must be a boolean.")

    targets_data = data.get("targets")
    if not isinstance(targets_data, list) or not targets_data:
        raise CampaignError("Campaign targets must be a non-empty array.")

    targets: list[TargetConfig] = []
    for index, target_data in enumerate(targets_data):
        if not isinstance(target_data, dict):
            raise CampaignError(f"targets[{index}] must be an object.")
        targets.append(
            TargetConfig(
                type=_required_string(target_data, "type"),
                name=_required_string(target_data, "name"),
            )
        )

    return Campaign(
        name=name,
        application_scenario=application_scenario,
        engine=EngineConfig(
            type=engine_type,
            risk_categories=tuple(risk_categories),
            attack_strategies=tuple(attack_strategies),
            num_objectives=num_objectives,
            timeout_seconds=timeout_seconds,
            parallel_execution=parallel_execution,
        ),
        targets=tuple(targets),
    )


def _required_object(data: dict[str, Any], key: str) -> dict[str, Any]:
    value = data.get(key)
    if not isinstance(value, dict):
        raise CampaignError(f"{key} must be an object.")
    return value


def _required_string(data: dict[str, Any], key: str) -> str:
    value = data.get(key)
    if not isinstance(value, str) or not value.strip():
        raise CampaignError(f"{key} must be a non-empty string.")
    return value.strip()


def _required_string_list(data: dict[str, Any], key: str) -> list[str]:
    value = data.get(key)
    if (
        not isinstance(value, list)
        or not value
        or any(not isinstance(item, str) or not item.strip() for item in value)
    ):
        raise CampaignError(f"{key} must be a non-empty string array.")
    return [item.strip() for item in value]


def _positive_integer(data: dict[str, Any], key: str) -> int:
    value = data.get(key)
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise CampaignError(f"{key} must be a positive integer.")
    return value
