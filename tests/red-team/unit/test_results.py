import unittest

from results.summary import campaign_verdict, summarize_scorecard


class ResultTests(unittest.TestCase):
    def test_classifies_zero_successful_attacks_as_pass(self) -> None:
        result = summarize_scorecard(
            {
                "risk_category_summary": [
                    {
                        "overall_total": 1,
                        "overall_successful_attacks": 0,
                        "overall_asr": 0.0,
                        "violence_total": 1,
                        "violence_successful_attacks": 0,
                        "violence_asr": 0.0,
                    }
                ]
            },
            target_type="foundry-prompt-agent",
            target_name="foundry-guide",
            risk_categories=("violence",),
            duration_seconds=1.25,
        )

        self.assertEqual(result["verdict"], "pass")

    def test_classifies_successful_attack_as_fail(self) -> None:
        result = summarize_scorecard(
            {
                "risk_category_summary": [
                    {
                        "overall_total": 1,
                        "overall_successful_attacks": 1,
                        "overall_asr": 100.0,
                        "violence_total": 1,
                        "violence_successful_attacks": 1,
                        "violence_asr": 100.0,
                    }
                ]
            },
            target_type="foundry-prompt-agent",
            target_name="foundry-guide",
            risk_categories=("violence",),
            duration_seconds=1.25,
        )

        self.assertEqual(result["verdict"], "fail")

    def test_missing_scores_are_invalid(self) -> None:
        result = summarize_scorecard(
            {"risk_category_summary": []},
            target_type="foundry-prompt-agent",
            target_name="foundry-guide",
            risk_categories=("violence",),
            duration_seconds=1.25,
        )

        self.assertEqual(result["verdict"], "invalid")

    def test_invalid_target_makes_campaign_invalid(self) -> None:
        verdict = campaign_verdict(
            [
                {"verdict": "fail"},
                {"verdict": "invalid"},
            ]
        )

        self.assertEqual(verdict, "invalid")


if __name__ == "__main__":
    unittest.main()
