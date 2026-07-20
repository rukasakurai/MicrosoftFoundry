import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from pyrit.models import AttackOutcome

from campaigns.config import EngineConfig, PolicyConfig
from engines.pyrit_engine import PyritEngine


class EngineTests(unittest.IsolatedAsyncioTestCase):
    @patch("engines.pyrit_engine.SelfAskTrueFalseScorer")
    @patch("engines.pyrit_engine.AttackScoringConfig")
    @patch("engines.pyrit_engine.ManyShotJailbreakAttack")
    @patch("engines.pyrit_engine.PromptSendingAttack")
    async def test_runs_only_configured_attacks(
        self,
        prompt_attack_type,
        jailbreak_attack_type,
        _scoring_config_type,
        _scorer_type,
    ) -> None:
        baseline_result = MagicMock(outcome=AttackOutcome.FAILURE)
        jailbreak_result = MagicMock(outcome=AttackOutcome.SUCCESS)
        prompt_attack_type.return_value.execute_async = AsyncMock(
            return_value=baseline_result
        )
        jailbreak_attack_type.return_value.execute_async = AsyncMock(
            return_value=jailbreak_result
        )
        memory = MagicMock()
        engine = PyritEngine(
            judge_target=MagicMock(),
            config=EngineConfig(
                type="pyrit",
                attacks=("baseline", "many-shot-jailbreak"),
                many_shot_examples=5,
                timeout_seconds=30,
            ),
            objective="Synthetic objective.",
            policy=PolicyConfig(
                category="test",
                true_description="The attack succeeded.",
                false_description="The attack failed.",
            ),
            memory=memory,
        )

        executions = await engine.run(MagicMock())
        engine.close()

        self.assertEqual(
            [execution.outcome for execution in executions],
            ["failure", "success"],
        )
        jailbreak_arguments = jailbreak_attack_type.call_args.kwargs
        self.assertEqual(jailbreak_arguments["example_count"], 5)
        memory.dispose_engine.assert_called_once()


if __name__ == "__main__":
    unittest.main()
