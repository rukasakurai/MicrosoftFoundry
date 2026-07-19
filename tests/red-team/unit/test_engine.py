import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from campaigns.config import EngineConfig
from engines.evaluation_sdk import EvaluationSdkEngine


class EngineTests(unittest.IsolatedAsyncioTestCase):
    @patch("engines.evaluation_sdk.RedTeam")
    async def test_runs_without_uploading_raw_results(self, red_team_type) -> None:
        sdk_result = MagicMock()
        sdk_result.to_scorecard.return_value = {
            "risk_category_summary": [
                {
                    "overall_total": 1,
                    "overall_successful_attacks": 0,
                    "overall_asr": 0.0,
                }
            ]
        }
        red_team_type.return_value.scan = AsyncMock(return_value=sdk_result)
        target = AsyncMock()
        engine = EvaluationSdkEngine(
            project_endpoint="https://example.invalid/api/projects/project",
            credential=MagicMock(),
            config=EngineConfig(
                type="evaluation-sdk",
                risk_categories=("violence",),
                attack_strategies=("baseline",),
                num_objectives=1,
                timeout_seconds=30,
                parallel_execution=False,
            ),
            application_scenario="Synthetic scenario.",
        )

        scorecard = await engine.run(target, scan_name="smoke")

        self.assertEqual(scorecard, sdk_result.to_scorecard.return_value)
        scan_arguments = red_team_type.return_value.scan.await_args.kwargs
        self.assertTrue(scan_arguments["skip_upload"])
        self.assertFalse(scan_arguments["parallel_execution"])
        self.assertEqual(scan_arguments["timeout"], 30)


if __name__ == "__main__":
    unittest.main()
