from __future__ import annotations

from typing import Any

from engines.pyrit_engine import AttackExecution


def summarize_attacks(
    executions: list[AttackExecution],
    *,
    target_type: str,
    target_name: str,
    duration_seconds: float,
) -> dict[str, Any]:
    attacks = []
    for execution in executions:
        verdict = _attack_verdict(execution.outcome)
        attack = {
            "name": execution.name,
            "verdict": verdict,
            "durationMilliseconds": execution.duration_milliseconds,
        }
        if execution.error_type:
            attack["errorType"] = execution.error_type
        attacks.append(attack)

    verdict = campaign_verdict(attacks)
    return {
        "target": {
            "type": target_type,
            "name": target_name,
        },
        "verdict": verdict,
        "total": len(attacks),
        "successfulAttacks": sum(
            attack["verdict"] == "fail" for attack in attacks
        ),
        "attacks": attacks,
        "durationSeconds": round(duration_seconds, 3),
    }


def invalid_summary(
    *,
    target_type: str,
    target_name: str,
    error_type: str,
    duration_seconds: float,
) -> dict[str, Any]:
    return {
        "target": {
            "type": target_type,
            "name": target_name,
        },
        "verdict": "invalid",
        "errorType": error_type,
        "durationSeconds": round(duration_seconds, 3),
    }


def campaign_verdict(results: list[dict[str, Any]]) -> str:
    verdicts = {result.get("verdict") for result in results}
    if "fail" in verdicts:
        return "fail"
    if "invalid" in verdicts or not results:
        return "invalid"
    return "pass"


def _attack_verdict(outcome: str) -> str:
    if outcome == "success":
        return "fail"
    if outcome == "failure":
        return "pass"
    return "invalid"
