#!/bin/bash
# Classify a Foundry agent run as pass / fail / invalid from its Responses API output
# items, so assistant prose isn't mistaken for a verified tool call.
# See docs/agent-mcp-oauth.md ("Evidence-safe validation") for the rationale.
# Usage:  ./classify-agent-run.sh < response.json
# Output: a secret-free JSON verdict (never tokens, consent links, or tenant ids).
# Exit:   0 = pass, 1 = fail, 2 = invalid/inconclusive.
set -euo pipefail

VERDICT=$(jq '
  (.output // []) as $o
  | ($o | map(select(.type == "mcp_call"))) as $calls
  | ($calls | map(select((.error // null) != null))) as $errs
  | { response_id: (.id // null),
      assistant_text_present: (($o | map(select(.type == "message")) | length) > 0),
      tool_calls: ($calls | length),
      tool_errors: ($errs | length),
      approval_requests: ($o | map(select(.type == "mcp_approval_request")) | length),
      consent_required: (($o | map(select(.type == "oauth_consent_request")) | length) > 0) }
  | . + { classification:
      (if .tool_errors > 0 then "fail" elif .tool_calls > 0 then "pass" else "invalid" end) }
')

echo "$VERDICT" | jq .
case "$(echo "$VERDICT" | jq -r .classification)" in
  pass) exit 0;; fail) exit 1;; *) exit 2;;
esac
