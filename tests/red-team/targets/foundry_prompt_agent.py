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
from pyrit.models import Message, MessagePiece
from pyrit.prompt_target import PromptTarget
from pyrit.prompt_target.common.target_capabilities import TargetCapabilities
from pyrit.prompt_target.common.target_configuration import TargetConfiguration


class TargetRequestError(RuntimeError):
    def __init__(
        self,
        status_code: int,
        service_error_codes: set[str] | None = None,
        source: str = "foundry",
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
        self.source = source


class TargetConnectionError(RuntimeError):
    pass


class TargetResponseError(RuntimeError):
    pass


class _FoundryResponsesTarget(PromptTarget):
    _TOKEN_SCOPE = "https://ai.azure.com/.default"
    _CONTENT_FILTER_CODES = {
        "ResponsibleAIPolicyViolation",
        "content_filter",
        "invalid_prompt",
    }

    def __init__(
        self,
        *,
        project_endpoint: str,
        credential: TokenCredential,
        max_output_tokens: int,
        source: str,
        content_filter_response: str | None = None,
        supports_conversation: bool = False,
    ) -> None:
        super().__init__(
            custom_configuration=TargetConfiguration(
                capabilities=TargetCapabilities(
                    supports_multi_turn=supports_conversation,
                    supports_editable_history=supports_conversation,
                    supports_system_prompt=supports_conversation,
                )
            )
        )
        self._project_endpoint = project_endpoint.rstrip("/")
        self._credential = credential
        self._max_output_tokens = max_output_tokens
        self._source = source
        self._content_filter_response = content_filter_response
        self._access_token: AccessToken | None = None

    async def _post(
        self,
        *,
        url: str,
        payload: dict[str, Any],
        headers: dict[str, str] | None = None,
    ) -> str:
        return await asyncio.to_thread(
            self._post_sync,
            url=url,
            payload=payload,
            headers=headers or {},
        )

    def _post_sync(
        self,
        *,
        url: str,
        payload: dict[str, Any],
        headers: dict[str, str],
    ) -> str:
        token = self._get_token()
        request = urllib.request.Request(
            url,
            data=json.dumps(payload).encode(),
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
                **headers,
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                response_payload = json.load(response)
        except urllib.error.HTTPError as error:
            error_codes = service_error_codes(error)
            if (
                error.code == 400
                and self._content_filter_response
                and self._CONTENT_FILTER_CODES.intersection(error_codes)
            ):
                return self._content_filter_response
            raise TargetRequestError(
                error.code,
                error_codes,
                source=self._source,
            ) from error
        except (urllib.error.URLError, TimeoutError) as error:
            raise TargetConnectionError("Unable to reach the Foundry target.") from error
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise TargetResponseError("Foundry target returned invalid JSON.") from error

        text = extract_response_text(response_payload)
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


class FoundryPromptAgentTarget(_FoundryResponsesTarget):
    _BLOCKED_RESPONSE = (
        "The target blocked the request through its configured content safety policy."
    )

    def __init__(
        self,
        *,
        project_endpoint: str,
        agent_name: str,
        credential: TokenCredential,
    ) -> None:
        super().__init__(
            project_endpoint=project_endpoint,
            credential=credential,
            max_output_tokens=1200,
            source="prompt_agent",
            content_filter_response=self._BLOCKED_RESPONSE,
        )
        self._agent_name = agent_name
        self._user_isolation_key = hashlib.sha256(
            f"red-team:{agent_name}".encode()
        ).hexdigest()

    async def _send_prompt_to_target_async(
        self,
        *,
        normalized_conversation: list[Message],
    ) -> list[Message]:
        request_piece = single_user_request(normalized_conversation)
        chat_key = uuid.UUID(request_piece.conversation_id).hex
        response_text = await self._post(
            url=(
                f"{self._project_endpoint}/agents/"
                f"{urllib.parse.quote(self._agent_name, safe='')}"
                "/endpoint/protocols/openai/responses?api-version=v1"
            ),
            payload={
                "input": piece_text(request_piece),
                "max_output_tokens": self._max_output_tokens,
            },
            headers={
                "x-ms-user-isolation-key": self._user_isolation_key,
                "x-ms-chat-isolation-key": chat_key,
            },
        )
        return [response_message(request_piece, response_text)]


class FoundryModelTarget(_FoundryResponsesTarget):
    def __init__(
        self,
        *,
        project_endpoint: str,
        model_name: str,
        credential: TokenCredential,
    ) -> None:
        super().__init__(
            project_endpoint=project_endpoint,
            credential=credential,
            max_output_tokens=256,
            source="judge_model",
            supports_conversation=True,
        )
        self._model_name = model_name

    async def _send_prompt_to_target_async(
        self,
        *,
        normalized_conversation: list[Message],
    ) -> list[Message]:
        request_piece = normalized_conversation[-1].get_piece(0)
        response_text = await self._post(
            url=f"{self._project_endpoint}/openai/v1/responses",
            payload=model_payload(
                normalized_conversation,
                model_name=self._model_name,
                max_output_tokens=self._max_output_tokens,
            ),
        )
        return [response_message(request_piece, response_text)]


def single_user_request(messages: list[Message]):
    pieces = [
        message.get_piece(0)
        for message in messages
        if message.get_piece(0).api_role == "user"
    ]
    if len(pieces) != 1:
        raise ValueError(
            "The Foundry prompt-agent target requires one single-turn user message."
        )
    request_piece = pieces[0]
    if request_piece.converted_value_data_type != "text":
        raise ValueError("The Foundry prompt-agent target accepts text only.")
    return request_piece


def model_payload(
    messages: list[Message],
    *,
    model_name: str,
    max_output_tokens: int,
) -> dict[str, Any]:
    instructions = []
    inputs = []
    for message in messages:
        piece = message.get_piece(0)
        if piece.converted_value_data_type != "text":
            raise ValueError("The Foundry model target accepts text only.")
        if piece.api_role in {"system", "developer"}:
            instructions.append(piece_text(piece))
            continue
        inputs.append(
            {
                "role": piece.api_role,
                "content": piece_text(piece),
            }
        )
    if not inputs:
        raise ValueError("The Foundry model target requires an input message.")

    payload: dict[str, Any] = {
        "model": model_name,
        "input": inputs,
        "max_output_tokens": max_output_tokens,
    }
    if instructions:
        payload["instructions"] = "\n\n".join(instructions)
    return payload


def piece_text(piece) -> str:
    value = piece.converted_value or piece.original_value
    if not isinstance(value, str) or not value.strip():
        raise ValueError("The Foundry target received empty text.")
    return value


def response_message(request_piece, response_text: str) -> Message:
    return Message(
        message_pieces=[
            MessagePiece(
                role="assistant",
                conversation_id=request_piece.conversation_id,
                original_value=response_text,
                converted_value=response_text,
                original_value_data_type="text",
                converted_value_data_type="text",
                prompt_target_identifier=request_piece.prompt_target_identifier,
                attack_identifier=request_piece.attack_identifier,
                prompt_metadata=request_piece.prompt_metadata,
            )
        ]
    )


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
