#!/bin/bash
#
# Evidence-safe classification of a Microsoft Foundry agent run.
#
# Assistant prose is NOT proof that a tool ran. For any tool-backed agent, the
# authoritative single-run evidence is the Responses API output items themselves
# (mcp_list_tools, mcp_approval_request, mcp_call with output or error,
# oauth_consent_request, and the final message). This script inspects those items
# and classifies the run as pass / fail / invalid so a plausible-looking answer is
# never mistaken for a verified tool invocation.
#
# For richer, server-side evidence see the Foundry portal Traces tab / Application
# Insights (provisioned by infra/ when enableObservability is on) and the built-in
# Tool Call Success / Accuracy evaluators. This script is the lightweight,
# CI-friendly complement for a single run.
#
# Scope: MCP tools (the item shapes are easy to detect). The taxonomy and structure
# generalize to OpenAPI / Function tools later.
#
# Usage:
#   ./classify-agent-run.sh < response.json
#   some_command_that_prints_the_responses_json | ./classify-agent-run.sh
#   ./classify-agent-run.sh --file response.json
#
# Input: a Responses API response JSON (the object returned by
#   POST {PROJECT_ENDPOINT}/openai/v1/responses), on stdin or via --file.
#
# Output: a secret-free JSON verdict on stdout. Never prints tokens, consent links,
#   or tenant-specific identifiers.
#
# Exit code (CI-friendly): 0 = pass, 1 = fail, 2 = invalid/inconclusive, 3 = usage/parse error.
#
# Classification:
#   pass    - a verifiable tool invocation (mcp_call) returned output and no error.
#   fail    - a verifiable tool invocation (mcp_call) returned an error.
#   invalid - assistant text and/or a pending approval/consent request, but NO
#             verifiable tool invocation or tool error (the false-confidence case).

set -euo pipefail

FILE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --file) FILE="$2"; shift 2;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1 (use --help)" >&2; exit 3;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 3
fi

if [ -n "$FILE" ]; then
  RESP=$(cat "$FILE")
else
  RESP=$(cat)
fi

if [ -z "${RESP// }" ] || ! echo "$RESP" | jq empty >/dev/null 2>&1; then
  echo "Error: input is not valid JSON." >&2
  exit 3
fi

# Derive a secret-free verdict from the output items.
#  - tool_calls   : number of mcp_call items
#  - tool_errors  : mcp_call items carrying a non-null error (or a failed status)
#  - tool_outputs : mcp_call items with output and no error
#  - approvals    : mcp_approval_request items (pending, not yet a verified call)
#  - consent      : whether an oauth_consent_request is present (boolean only; the
#                   consent link itself is intentionally NOT emitted)
#  - text_present : whether a final assistant message exists
VERDICT=$(echo "$RESP" | jq '
  (.output // []) as $o
  | ($o | map(select(.type == "mcp_call"))) as $calls
  | ($calls | map(select((.error // null) != null or (.status // "") == "failed" or (.status // "") == "error"))) as $errs
  | {
      response_id: (.id // null),
      status: (.status // null),
      assistant_text_present: (($o | map(select(.type == "message")) | length) > 0),
      tool_calls: ($calls | length),
      tool_outputs: (($calls | length) - ($errs | length)),
      tool_errors: ($errs | length),
      approval_requests: (($o | map(select(.type == "mcp_approval_request")) | length)),
      consent_required: (($o | map(select(.type == "oauth_consent_request")) | length) > 0),
      tools_listed: (($o | map(select(.type == "mcp_list_tools")) | length) > 0)
    }
  | . + {
      classification:
        (if .tool_errors > 0 then "fail"
         elif .tool_calls > 0 then "pass"
         else "invalid" end),
      notes:
        ([ (if .consent_required then "oauth_consent_request present: caller must consent; no verified tool call yet" else empty end),
           (if .approval_requests > 0 then "mcp_approval_request present: tool-call approval pending" else empty end),
           (if .tool_calls == 0 and .assistant_text_present then "assistant text only: no verifiable tool invocation (do not treat as proof the tool ran)" else empty end)
         ])
    }
')

echo "$VERDICT" | jq .

CLASS=$(echo "$VERDICT" | jq -r '.classification')
case "$CLASS" in
  pass) exit 0;;
  fail) exit 1;;
  invalid) exit 2;;
  *) exit 3;;
esac
