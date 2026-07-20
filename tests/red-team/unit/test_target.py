import asyncio
import io
import json
import time
import unittest
from unittest.mock import MagicMock, patch

from azure.core.credentials import AccessToken
from pyrit.memory import CentralMemory, SQLiteMemory
from pyrit.models import Message

from targets.foundry_prompt_agent import (
    FoundryModelTarget,
    FoundryPromptAgentTarget,
    TargetRequestError,
    extract_response_text,
)


class TargetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.memory = SQLiteMemory(db_path=":memory:", silent=True)
        CentralMemory.set_memory_instance(cls.memory)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.memory.dispose_engine()

    def test_prompt_agent_invokes_stable_endpoint(self) -> None:
        credential = credential_mock()
        response = response_mock({"output_text": "SAFE"})
        target = FoundryPromptAgentTarget(
            project_endpoint="https://example.invalid/api/projects/project",
            agent_name="foundry-guide",
            credential=credential,
        )
        message = Message.from_prompt(prompt="synthetic prompt", role="user")

        with patch("urllib.request.urlopen", return_value=response) as urlopen:
            result = asyncio.run(
                target._send_prompt_to_target_async(
                    normalized_conversation=[message]
                )
            )

        self.assertEqual(result[0].get_piece(0).converted_value, "SAFE")
        request = urlopen.call_args.args[0]
        self.assertEqual(
            request.full_url,
            "https://example.invalid/api/projects/project/agents/"
            "foundry-guide/endpoint/protocols/openai/responses?api-version=v1",
        )
        self.assertEqual(
            json.loads(request.data)["input"],
            "synthetic prompt",
        )
        self.assertEqual(request.get_header("Authorization"), "Bearer token")

    def test_model_target_sends_conversation_to_responses_api(self) -> None:
        response = response_mock({"output_text": "FALSE"})
        target = FoundryModelTarget(
            project_endpoint="https://example.invalid/api/projects/project",
            model_name="model",
            credential=credential_mock(),
        )
        messages = [
            Message.from_prompt(prompt="policy", role="system"),
            Message.from_prompt(prompt="response", role="user"),
        ]

        with patch("urllib.request.urlopen", return_value=response) as urlopen:
            result = asyncio.run(
                target._send_prompt_to_target_async(
                    normalized_conversation=messages
                )
            )

        self.assertEqual(result[0].get_piece(0).converted_value, "FALSE")
        payload = json.loads(urlopen.call_args.args[0].data)
        self.assertEqual(payload["model"], "model")
        self.assertEqual(len(payload["input"]), 1)
        self.assertEqual(payload["input"][0]["role"], "user")
        self.assertEqual(payload["instructions"], "policy")

    def test_content_filter_rejection_becomes_blocked_response(self) -> None:
        target = FoundryPromptAgentTarget(
            project_endpoint="https://example.invalid/api/projects/project",
            agent_name="foundry-guide",
            credential=credential_mock(),
        )
        error = urllib_error(
            400,
            {
                "error": {
                    "code": "invalid_prompt",
                    "innererror": {
                        "code": "ResponsibleAIPolicyViolation",
                    },
                }
            },
        )
        message = Message.from_prompt(prompt="synthetic prompt", role="user")

        with patch("urllib.request.urlopen", side_effect=error):
            result = asyncio.run(
                target._send_prompt_to_target_async(
                    normalized_conversation=[message]
                )
            )

        self.assertIn("blocked", result[0].get_piece(0).converted_value)

    def test_other_bad_request_remains_invalid(self) -> None:
        target = FoundryPromptAgentTarget(
            project_endpoint="https://example.invalid/api/projects/project",
            agent_name="foundry-guide",
            credential=credential_mock(),
        )
        error = urllib_error(400, {"error": {"code": "InvalidRequest"}})
        message = Message.from_prompt(prompt="synthetic prompt", role="user")

        with patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(TargetRequestError) as raised:
                asyncio.run(
                    target._send_prompt_to_target_async(
                        normalized_conversation=[message]
                    )
                )

        self.assertEqual(
            raised.exception.service_error_codes,
            {"InvalidRequest"},
        )
        self.assertEqual(raised.exception.source, "prompt_agent")

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


def credential_mock():
    credential = MagicMock()
    credential.get_token.return_value = AccessToken(
        "token",
        int(time.time()) + 3600,
    )
    return credential


def response_mock(payload: dict):
    response = MagicMock()
    response.__enter__.return_value.read.return_value = json.dumps(payload).encode()
    return response


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
