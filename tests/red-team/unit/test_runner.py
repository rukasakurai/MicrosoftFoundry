import os
import unittest
from unittest.mock import patch

from campaigns.config import TargetConfig
from run import resolved_target_name


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

if __name__ == "__main__":
    unittest.main()
