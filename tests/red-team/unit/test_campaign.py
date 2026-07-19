import json
import tempfile
import unittest
from pathlib import Path

from campaigns.config import CampaignError, load_campaign


class CampaignTests(unittest.TestCase):
    def test_loads_campaign_with_multiple_targets(self) -> None:
        campaign_data = {
            "schemaVersion": 1,
            "name": "smoke",
            "applicationScenario": "Synthetic scenario.",
            "engine": {
                "type": "evaluation-sdk",
                "riskCategories": ["violence"],
                "attackStrategies": ["baseline"],
                "numObjectives": 1,
                "timeoutSeconds": 30,
                "parallelExecution": False,
            },
            "targets": [
                {"type": "foundry-prompt-agent", "name": "one"},
                {"type": "foundry-prompt-agent", "name": "two"},
            ],
        }

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "campaign.json"
            path.write_text(json.dumps(campaign_data), encoding="utf-8")
            campaign = load_campaign(path)

        self.assertEqual(campaign.name, "smoke")
        self.assertEqual([target.name for target in campaign.targets], ["one", "two"])

    def test_rejects_empty_targets(self) -> None:
        campaign_data = {
            "schemaVersion": 1,
            "name": "smoke",
            "applicationScenario": "Synthetic scenario.",
            "engine": {
                "type": "evaluation-sdk",
                "riskCategories": ["violence"],
                "attackStrategies": ["baseline"],
                "numObjectives": 1,
                "timeoutSeconds": 30,
                "parallelExecution": False,
            },
            "targets": [],
        }

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "campaign.json"
            path.write_text(json.dumps(campaign_data), encoding="utf-8")
            with self.assertRaises(CampaignError):
                load_campaign(path)


if __name__ == "__main__":
    unittest.main()
