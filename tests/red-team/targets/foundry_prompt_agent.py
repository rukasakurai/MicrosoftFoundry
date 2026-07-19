from __future__ import annotations

import asyncio
import hashlib
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from typing import Any

from azure.core.credentials import AccessToken, TokenCredential


class TargetRequestError(RuntimeError):
    def __init__(
        self,
        status_code: int,
        service_error_codes: set[str] | None = None,
    ) -> None:
        service_error_codes = service_error_codes or set()
        code_suffix = (
            f" Service codes: {', '.join(sorted(service_error_codes))}."
            if service_error_codes
            else ""
        )
        super().__init__(f"Foundry target returned HTTP {status_code}.{code_suffix}")
        self.status_code = status_code
        self.service_error_codes = service_error_codes


class TargetConnectionError(RuntimeError):
    pass


class TargetResponseError(RuntimeError):
    pass


class FoundryPromptAgentTarget:
    _TOKEN_SCOPE = "https://ai.azure.com/.default"
    _CONTENT_FILTER_CODES = {
        "ResponsibleAIPolicyViolation",
        "content_filter",
    }
    _CONTENT_FILTER_RESPONSE = (
        "The target blocked the request through its configured content safety policy."
    )

    def __init__(
        self,
        *,
        project_endpoint: str,
        agent_name: str,
        credential: TokenCredential,
        timeout_seconds: int = 120,
    ) -> None:
        self._project_endpoint = project_endpoint.rstrip("/")
        self._agent_name = agent_name
        self._credential = credential
        self._timeout_seconds = timeout_seconds
        self._access_token: AccessToken | None = None
        self._user_isolation_key = hashlib.sha256(
            f"red-team:{agent_name}".encode()
        ).hexdigest()

    async def __call__(
        self,
        *,
        messages: list[dict[str, Any]],
        stream: bool = False,
        session_state: Any = None,
        context: Any = None,
    ) -> dict[str, list[dict[str, str]]]:
        del session_state, context
        if stream:
            raise ValueError("The Foundry prompt-agent target does not stream.")

        prompt = latest_user_message(messages)
        response_text = await asyncio.to_thread(self._send, prompt)
        return {
            "messages": [
                {
                    "role": "assistant",
                    "content": response_text,
                }
            ]
        }

    def _send(self, prompt: str) -> str:
        token = self._get_token()
        request = urllib.request.Request(
            (
                f"{self._project_endpoint}/agents/"
                f"{urllib.parse.quote(self._agent_name, safe='')}"
                "/endpoint/protocols/openai/responses?api-version=v1"
            ),
            data=json.dumps({"input": prompt}).encode(),
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                "x-ms-user-isolation-key": self._user_isolation_key,
                "x-ms-chat-isolation-key": uuid.uuid4().hex,
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(
                request,
                timeout=self._timeout_seconds,
            ) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as error:
            error_codes = service_error_codes(error)
            if (
                error.code == 400
                and self._CONTENT_FILTER_CODES.intersection(error_codes)
            ):
                return self._CONTENT_FILTER_RESPONSE
            raise TargetRequestError(error.code, error_codes) from error
        except (urllib.error.URLError, TimeoutError) as error:
            raise TargetConnectionError("Unable to reach the Foundry target.") from error
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise TargetResponseError("Foundry target returned invalid JSON.") from error

        text = extract_response_text(payload)
        if not text:
            raise TargetResponseError("Foundry target returned no output text.")
        return text

    def _get_token(self) -> str:
        if (
            self._access_token is None
            or self._access_token.expires_on <= int(time.time()) + 300
        ):
            self._access_token = self._credential.get_token(self._TOKEN_SCOPE)
        return self._access_token.token


def latest_user_message(messages: list[dict[str, Any]]) -> str:
    user_messages = [
        message.get("content")
        for message in messages
        if message.get("role") == "user"
        and isinstance(message.get("content"), str)
        and message["content"].strip()
    ]
    if len(user_messages) != 1:
        raise ValueError(
            "The Foundry prompt-agent target requires one single-turn user message."
        )
    return user_messages[0]


def extract_response_text(payload: Any) -> str:
    if not isinstance(payload, (dict, list)):
        return ""

    if isinstance(payload, dict):
        output_text = payload.get("output_text")
        if isinstance(output_text, str) and output_text.strip():
            return output_text.strip()

        text = payload.get("text")
        if (
            payload.get("type") in {"output_text", "text"}
            and isinstance(text, str)
            and text.strip()
        ):
            return text.strip()

        values = payload.values()
    else:
        values = payload

    parts = [extract_response_text(value) for value in values]
    return "\n".join(dict.fromkeys(part for part in parts if part))


def service_error_codes(error: urllib.error.HTTPError) -> set[str]:
    try:
        payload = json.loads(error.read(65536))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return set()

    codes: set[str] = set()

    def collect(value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if (
                    key.lower() == "code"
                    and isinstance(child, str)
                    and re.fullmatch(r"[A-Za-z0-9_.-]+", child)
                ):
                    codes.add(child)
                else:
                    collect(child)
        elif isinstance(value, list):
            for child in value:
                collect(child)

    collect(payload)
    return codes
