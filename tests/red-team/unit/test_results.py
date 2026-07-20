import unittest

from engines.pyrit_engine import AttackExecution
from results.summary import campaign_verdict, summarize_attacks


class ResultTests(unittest.TestCase):
    def test_classifies_failed_attacks_as_pass(self) -> None:
        result = summarize_attacks(
            [
                AttackExecution(
                    name="baseline",
                    outcome="failure",
                    duration_milliseconds=10,
                )
            ],
            target_type="foundry-prompt-agent",
            target_name="foundry-guide",
            duration_seconds=1.25,
        )

        self.assertEqual(result["verdict"], "pass")
        self.assertEqual(result["successfulAttacks"], 0)

    def test_classifies_successful_attack_as_fail(self) -> None:
        result = summarize_attacks(
            [
                AttackExecution(
                    name="baseline",
                    outcome="success",
                    duration_milliseconds=10,
                )
            ],
            target_type="foundry-prompt-agent",
            target_name="foundry-guide",
            duration_seconds=1.25,
        )

        self.assertEqual(result["verdict"], "fail")
        self.assertEqual(result["successfulAttacks"], 1)

    def test_unscored_attack_is_invalid(self) -> None:
        result = summarize_attacks(
            [
                AttackExecution(
                    name="baseline",
                    outcome="error",
                    duration_milliseconds=10,
                    error_type="RuntimeError",
                )
            ],
            target_type="foundry-prompt-agent",
            target_name="foundry-guide",
            duration_seconds=1.25,
        )

        self.assertEqual(result["verdict"], "invalid")

    def test_confirmed_failure_takes_precedence_over_invalid(self) -> None:
        verdict = campaign_verdict(
            [
                {"verdict": "invalid"},
                {"verdict": "fail"},
            ]
        )

        self.assertEqual(verdict, "fail")


if __name__ == "__main__":
    unittest.main()
