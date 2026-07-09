#!/bin/bash
# Verify a Microsoft Foundry Responses API run from its JSON output.
#
# Default mode preserves the original evidence-safe MCP/tool validation:
#   pass    = at least one mcp_call and no mcp_call errors
#   fail    = an mcp_call returned an error
#   invalid = no verifiable mcp_call evidence
#
# Text expectations make plain synthetic runs deterministic without printing prompt or
# response content. Use these for Purview/governance smoke tests where the evidence is
# a marker echoed in an assistant message rather than an MCP tool call.
#
# Usage:
#   ./scripts/verify-agent-run.sh < response.json
#   ./scripts/verify-agent-run.sh --expect-text PURVIEW-FOUNDRY-LAB-2026-07-09-001 < response.json
#   ./scripts/verify-agent-run.sh --expect-regex 'PURVIEW-FOUNDRY-LAB-[0-9-]+' < response.json
#   ./scripts/verify-agent-run.sh --require-tool-call --expect-text knowledge_base_retrieve < response.json
#   ./scripts/verify-agent-run.sh --self-test
#
# Output: a secret-free JSON verdict (never tokens, consent links, prompts, or full
# assistant text).
# Exit:   0 = pass, 1 = fail, 2 = invalid/inconclusive.
set -euo pipefail

EXPECT_TEXTS=()
EXPECT_REGEXES=()
REQUIRE_TOOL_CALL=""

usage() {
  sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
}

json_array() {
  if [ "$#" -eq 0 ]; then
    printf '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -s .
  fi
}

verify_file() {
  local input_file="$1"
  local expect_texts_json="$2"
  local expect_regexes_json="$3"
  local require_tool_call="$4"

  jq \
    --argjson expect_texts "$expect_texts_json" \
    --argjson expect_regexes "$expect_regexes_json" \
    --argjson require_tool_call "$require_tool_call" '
    def message_texts:
      [
        (.output // [])[]
        | select(.type == "message")
        | (.content // [])[]
        | (.text? // .content? // empty)
        | select(type == "string")
      ];

    (.output // []) as $o
    | message_texts as $texts
    | ($texts | join("\n")) as $joined_text
    | ($o | map(select(.type == "mcp_call"))) as $calls
    | ($calls | map(select((.error // null) != null))) as $errs
    | ($expect_texts | map(. as $needle | $joined_text | contains($needle))) as $text_matches
    | ($expect_regexes | map(. as $regex | $joined_text | test($regex))) as $regex_matches
    | {
        response_id: (.id // null),
        response_status: (.status // null),
        assistant_text_present: (($texts | length) > 0),
        assistant_message_count: (($o | map(select(.type == "message")) | length)),
        tool_calls: ($calls | length),
        tool_errors: ($errs | length),
        approval_requests: ($o | map(select(.type == "mcp_approval_request")) | length),
        consent_required: (($o | map(select(.type == "oauth_consent_request")) | length) > 0),
        expected_texts_checked: ($expect_texts | length),
        expected_texts_matched: ($text_matches | map(select(.)) | length),
        expected_regexes_checked: ($expect_regexes | length),
        expected_regexes_matched: ($regex_matches | map(select(.)) | length),
        require_tool_call: $require_tool_call
      }
    | . + {
        verdict:
          (if .response_status == "failed" or .response_status == "cancelled" or .tool_errors > 0 then
             "fail"
           elif .response_status != null and .response_status != "completed" then
             "invalid"
           elif ($require_tool_call and .tool_calls == 0) then
             "invalid"
           elif .expected_texts_matched < .expected_texts_checked then
             "invalid"
           elif .expected_regexes_matched < .expected_regexes_checked then
             "invalid"
           elif (.expected_texts_checked + .expected_regexes_checked) > 0 or .tool_calls > 0 then
             "pass"
           else
             "invalid"
           end)
      }
  ' "$input_file"
}

run_self_test() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  cat > "$tmpdir/tool-pass.json" <<'JSON'
{"id":"resp_tool_pass","output":[{"type":"mcp_call","name":"demo","output":"ok"},{"type":"message","content":[{"type":"output_text","text":"done"}]}]}
JSON
  cat > "$tmpdir/tool-fail.json" <<'JSON'
{"id":"resp_tool_fail","output":[{"type":"mcp_call","name":"demo","error":{"message":"nope"}}]}
JSON
  cat > "$tmpdir/text-pass.json" <<'JSON'
{"id":"resp_text_pass","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"Synthetic marker PURVIEW-FOUNDRY-LAB-2026-07-09-001 observed."}]}]}
JSON
  cat > "$tmpdir/text-invalid.json" <<'JSON'
{"id":"resp_text_invalid","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"No marker here."}]}]}
JSON
  cat > "$tmpdir/text-incomplete.json" <<'JSON'
{"id":"resp_text_incomplete","status":"incomplete","output":[{"type":"message","content":[{"type":"output_text","text":"Synthetic marker PURVIEW-FOUNDRY-LAB-2026-07-09-001 observed."}]}]}
JSON

  "$0" < "$tmpdir/tool-pass.json" >/dev/null
  if "$0" < "$tmpdir/tool-fail.json" >/dev/null; then
    echo "Expected tool-fail to fail" >&2
    return 1
  fi
  "$0" --expect-text PURVIEW-FOUNDRY-LAB-2026-07-09-001 < "$tmpdir/text-pass.json" >/dev/null
  if "$0" --expect-text PURVIEW-FOUNDRY-LAB-2026-07-09-001 < "$tmpdir/text-invalid.json" >/dev/null; then
    echo "Expected text-invalid to be inconclusive" >&2
    return 1
  fi
  if "$0" --expect-text PURVIEW-FOUNDRY-LAB-2026-07-09-001 < "$tmpdir/text-incomplete.json" >/dev/null; then
    echo "Expected text-incomplete to be inconclusive" >&2
    return 1
  fi

  echo '{"verdict":"pass","self_test":true}' | jq .
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --expect-text)
      EXPECT_TEXTS+=("${2:?missing value for --expect-text}")
      shift 2
      ;;
    --expect-regex)
      EXPECT_REGEXES+=("${2:?missing value for --expect-regex}")
      shift 2
      ;;
    --require-tool-call)
      REQUIRE_TOOL_CALL=true
      shift
      ;;
    --no-require-tool-call)
      REQUIRE_TOOL_CALL=false
      shift
      ;;
    --self-test)
      run_self_test
      exit 0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$REQUIRE_TOOL_CALL" ]; then
  if [ "${#EXPECT_TEXTS[@]}" -eq 0 ] && [ "${#EXPECT_REGEXES[@]}" -eq 0 ]; then
    REQUIRE_TOOL_CALL=true
  else
    REQUIRE_TOOL_CALL=false
  fi
fi

INPUT_FILE="$(mktemp)"
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

VERDICT="$(
  verify_file \
    "$INPUT_FILE" \
    "$(json_array "${EXPECT_TEXTS[@]}")" \
    "$(json_array "${EXPECT_REGEXES[@]}")" \
    "$REQUIRE_TOOL_CALL"
)"

echo "$VERDICT" | jq .
case "$(echo "$VERDICT" | jq -r .verdict)" in
  pass) exit 0;;
  fail) exit 1;;
  *) exit 2;;
esac
