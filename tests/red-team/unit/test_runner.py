import os
import unittest
from unittest.mock import patch

from campaigns.config import TargetConfig
from run import resolved_target_name
from results.summary import summarize_attacks


class RunnerTests(unittest.TestCase):
    def test_azd_override_applies_to_canonical_foundry_guide_target(self) -> None:
        config = TargetConfig(type="foundry-prompt-agent", name="foundry-guide")

        with patch.dict(
            os.environ,
            {"FOUNDRY_GUIDE_AGENT_NAME": "custom-guide"},
        ):
            self.assertEqual(resolved_target_name(config), "custom-guide")

    def test_azd_override_does_not_replace_other_targets(self) -> None:
        config = TargetConfig(type="foundry-prompt-agent", name="second-agent")

        with patch.dict(
            os.environ,
            {"FOUNDRY_GUIDE_AGENT_NAME": "custom-guide"},
        ):
            self.assertEqual(resolved_target_name(config), "second-agent")

    def test_summary_uses_public_campaign_label(self) -> None:
        config = TargetConfig(type="foundry-prompt-agent", name="foundry-guide")

        with patch.dict(
            os.environ,
            {"FOUNDRY_GUIDE_AGENT_NAME": "private-environment-name"},
        ):
            resolved_name = resolved_target_name(config)

        summary = summarize_attacks(
            [],
            target_type=config.type,
            target_name=config.name,
            duration_seconds=0,
        )

        self.assertEqual(resolved_name, "private-environment-name")
        self.assertEqual(summary["target"]["name"], "foundry-guide")

if __name__ == "__main__":
    unittest.main()
