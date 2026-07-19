import asyncio
import io
import json
import time
import unittest
from unittest.mock import MagicMock, patch

from azure.core.credentials import AccessToken
from targets.foundry_prompt_agent import (
    FoundryPromptAgentTarget,
    TargetRequestError,
    extract_response_text,
    latest_user_message,
)


class TargetTests(unittest.TestCase):
    def test_gets_latest_user_message(self) -> None:
        prompt = latest_user_message(
            [
                {"role": "system", "content": "system"},
                {"role": "user", "content": "prompt"},
            ]
        )

        self.assertEqual(prompt, "prompt")

    def test_extracts_nested_output_text(self) -> None:
        text = extract_response_text(
            {
                "output": [
                    {
                        "content": [
                            {
                                "type": "output_text",
                                "text": "FOUND",
                            }
                        ]
                    }
                ]
            }
        )

        self.assertEqual(text, "FOUND")

    def test_rejects_missing_user_message(self) -> None:
        with self.assertRaises(ValueError):
            latest_user_message([{"role": "assistant", "content": "reply"}])

    def test_rejects_multi_turn_messages(self) -> None:
        with self.assertRaises(ValueError):
            latest_user_message(
                [
                    {"role": "user", "content": "first"},
                    {"role": "assistant", "content": "reply"},
                    {"role": "user", "content": "second"},
                ]
            )

    def test_callback_invokes_stable_agent_endpoint(self) -> None:
        credential = MagicMock()
        credential.get_token.return_value = AccessToken(
            "token",
            int(time.time()) + 3600,
        )
        response = MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps(
            {"output_text": "SAFE"}
        ).encode()
        target = FoundryPromptAgentTarget(
            project_endpoint="https://example.invalid/api/projects/project",
            agent_name="foundry-guide",
            credential=credential,
        )

        with patch("urllib.request.urlopen", return_value=response) as urlopen:
            result = asyncio.run(
                target(
                    messages=[{"role": "user", "content": "synthetic prompt"}]
                )
            )

        self.assertEqual(result["messages"][0]["content"], "SAFE")
        request = urlopen.call_args.args[0]
        self.assertEqual(
            request.full_url,
            "https://example.invalid/api/projects/project/agents/"
            "foundry-guide/endpoint/protocols/openai/responses?api-version=v1",
        )
        self.assertEqual(json.loads(request.data), {"input": "synthetic prompt"})
        self.assertEqual(request.get_header("Authorization"), "Bearer token")
        self.assertIsNotNone(request.get_header("X-ms-user-isolation-key"))
        self.assertIsNotNone(request.get_header("X-ms-chat-isolation-key"))

    def test_content_filter_rejection_becomes_blocked_response(self) -> None:
        credential = MagicMock()
        credential.get_token.return_value = AccessToken(
            "token",
            int(time.time()) + 3600,
        )
        target = FoundryPromptAgentTarget(
            project_endpoint="https://example.invalid/api/projects/project",
            agent_name="foundry-guide",
            credential=credential,
        )
        error = urllib_error(
            400,
            {
                "error": {
                    "code": "content_filter",
                    "innererror": {
                        "code": "ResponsibleAIPolicyViolation",
                    },
                }
            },
        )

        with patch("urllib.request.urlopen", side_effect=error):
            result = asyncio.run(
                target(messages=[{"role": "user", "content": "synthetic prompt"}])
            )

        self.assertIn("blocked", result["messages"][0]["content"])

    def test_other_bad_request_remains_invalid(self) -> None:
        credential = MagicMock()
        credential.get_token.return_value = AccessToken(
            "token",
            int(time.time()) + 3600,
        )
        target = FoundryPromptAgentTarget(
            project_endpoint="https://example.invalid/api/projects/project",
            agent_name="foundry-guide",
            credential=credential,
        )
        error = urllib_error(400, {"error": {"code": "InvalidRequest"}})

        with patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(TargetRequestError) as raised:
                asyncio.run(
                    target(
                        messages=[{"role": "user", "content": "synthetic prompt"}]
                    )
                )

        self.assertEqual(
            raised.exception.service_error_codes,
            {"InvalidRequest"},
        )


def urllib_error(status_code: int, payload: dict) -> Exception:
    import urllib.error

    return urllib.error.HTTPError(
        url="https://example.invalid",
        code=status_code,
        msg="error",
        hdrs=None,
        fp=io.BytesIO(json.dumps(payload).encode()),
    )


if __name__ == "__main__":
    unittest.main()
