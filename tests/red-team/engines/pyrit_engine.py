from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass

from pyrit.executor.attack import ManyShotJailbreakAttack, PromptSendingAttack
from pyrit.executor.attack.core import AttackScoringConfig
from pyrit.memory import CentralMemory, SQLiteMemory
from pyrit.models import AttackOutcome
from pyrit.prompt_target import PromptTarget
from pyrit.score import SelfAskTrueFalseScorer, TrueFalseQuestion

from campaigns.config import CampaignError, EngineConfig, PolicyConfig


@dataclass(frozen=True)
class AttackExecution:
    name: str
    outcome: str
    duration_milliseconds: int
    error_type: str | None = None


def initialize_pyrit_memory() -> SQLiteMemory:
    memory = SQLiteMemory(db_path=":memory:", silent=True)
    CentralMemory.set_memory_instance(memory)
    return memory


class PyritEngine:
    def __init__(
        self,
        *,
        judge_target: PromptTarget,
        config: EngineConfig,
        objective: str,
        policy: PolicyConfig,
        memory: SQLiteMemory,
    ) -> None:
        self._config = config
        self._objective = objective
        self._memory = memory
        self._scoring_config = AttackScoringConfig(
            objective_scorer=SelfAskTrueFalseScorer(
                chat_target=judge_target,
                true_false_question=TrueFalseQuestion(
                    category=policy.category,
                    true_description=policy.true_description,
                    false_description=policy.false_description,
                ),
            )
        )

    async def run(self, target: PromptTarget) -> list[AttackExecution]:
        executions = []
        for attack_name in self._config.attacks:
            started = time.monotonic()
            try:
                attack = self._create_attack(attack_name, target)
                result = await asyncio.wait_for(
                    attack.execute_async(objective=self._objective),
                    timeout=self._config.timeout_seconds,
                )
                executions.append(
                    AttackExecution(
                        name=attack_name,
                        outcome=result.outcome.value,
                        duration_milliseconds=round(
                            (time.monotonic() - started) * 1000
                        ),
                    )
                )
            except Exception as error:
                executions.append(
                    AttackExecution(
                        name=attack_name,
                        outcome=AttackOutcome.ERROR.value,
                        duration_milliseconds=round(
                            (time.monotonic() - started) * 1000
                        ),
                        error_type=sanitized_error_type(error),
                    )
                )
        return executions

    def close(self) -> None:
        self._memory.dispose_engine()

    def _create_attack(self, name: str, target: PromptTarget):
        common = {
            "objective_target": target,
            "attack_scoring_config": self._scoring_config,
            "max_attempts_on_failure": 0,
        }
        if name == "baseline":
            return PromptSendingAttack(**common)
        if name == "many-shot-jailbreak":
            return ManyShotJailbreakAttack(
                **common,
                example_count=self._config.many_shot_examples,
            )
        raise CampaignError(f"Unsupported PyRIT attack: {name}.")


def sanitized_error_type(error: Exception) -> str:
    current: BaseException | None = error
    deepest = type(error).__name__
    while current is not None:
        deepest = type(current).__name__
        source = getattr(current, "source", None)
        codes = getattr(current, "service_error_codes", set())
        if source and codes:
            return f"{source}:{','.join(sorted(codes))}"
        current = current.__cause__
    return deepest
