#!/bin/bash
#
# Classify a Microsoft Foundry agent run as pass / fail / invalid from its Responses
# API output items, so assistant prose is never mistaken for a verified tool call.
# See docs/agent-mcp-oauth.md ("Evidence-safe validation") for the rationale.
#
# Usage:   ./classify-agent-run.sh < response.json
#          ./classify-agent-run.sh --file response.json
# Input:   a Responses API response JSON (from POST .../openai/v1/responses).
# Output:  a secret-free JSON verdict (never tokens, consent links, or tenant ids).
# Exit:    0 = pass, 1 = fail, 2 = invalid/inconclusive, 3 = usage/parse error.

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
      consent_required: (($o | map(select(.type == "oauth_consent_request")) | length) > 0)
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
