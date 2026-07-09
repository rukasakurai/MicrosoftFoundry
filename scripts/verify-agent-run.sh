#!/bin/bash
# Verify a Microsoft Foundry Responses API JSON result without printing prompt text.
# Default: evidence-safe MCP/tool validation. With --expect-text: marker validation
# for plain synthetic runs. Exit: 0=pass, 1=fail, 2=invalid/inconclusive.
set -euo pipefail

EXPECT_TEXT=""
SELF_TEST=false

usage() {
  cat <<'EOF'
Usage:
  verify-agent-run.sh < response.json
  verify-agent-run.sh --expect-text MARKER < response.json
  verify-agent-run.sh --self-test
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --expect-text) EXPECT_TEXT="${2:?missing value for --expect-text}"; shift 2;;
    --self-test) SELF_TEST=true; shift;;
    --help|-h) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2;;
  esac
done

verify() {
  jq --arg expect_text "$EXPECT_TEXT" '
    def texts: [(.output // [])[] | select(.type == "message") | (.content // [])[] | (.text? // .content? // empty) | select(type == "string")];
    (.output // []) as $o
    | texts as $texts
    | ($o | map(select(.type == "mcp_call"))) as $calls
    | ($calls | map(select((.error // null) != null))) as $errs
    | ($expect_text != "") as $checks_text
    | {
        response_id: (.id // null),
        response_status: (.status // null),
        assistant_text_present: (($texts | length) > 0),
        assistant_message_count: ($o | map(select(.type == "message")) | length),
        tool_calls: ($calls | length),
        tool_errors: ($errs | length),
        approval_requests: ($o | map(select(.type == "mcp_approval_request")) | length),
        consent_required: (($o | map(select(.type == "oauth_consent_request")) | length) > 0),
        expected_text_checked: $checks_text,
        expected_text_matched: (if $checks_text then (($texts | join("\n")) | contains($expect_text)) else false end)
      }
    | . + { verdict:
        (if .response_status == "failed" or .response_status == "cancelled" or .tool_errors > 0 then "fail"
         elif .response_status != null and .response_status != "completed" then "invalid"
         elif .expected_text_checked then (if .expected_text_matched then "pass" else "invalid" end)
         elif .tool_calls > 0 then "pass"
         else "invalid" end)
      }'
}

expect_exit() {
  local expected="$1"; shift
  set +e
  "$@" >/dev/null
  local actual=$?
  set -e
  if [ "$actual" -ne "$expected" ]; then
    echo "Expected exit $expected, got $actual: $*" >&2
    exit 1
  fi
}

if [ "$SELF_TEST" = true ]; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  printf '%s\n' '{"id":"tool-pass","output":[{"type":"mcp_call","output":"ok"}]}' > "$tmpdir/tool-pass.json"
  printf '%s\n' '{"id":"tool-fail","output":[{"type":"mcp_call","error":{"message":"nope"}}]}' > "$tmpdir/tool-fail.json"
  printf '%s\n' '{"id":"text-pass","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"MARKER"}]}]}' > "$tmpdir/text-pass.json"
  printf '%s\n' '{"id":"text-invalid","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"no marker"}]}]}' > "$tmpdir/text-invalid.json"
  printf '%s\n' '{"id":"text-incomplete","status":"incomplete","output":[{"type":"message","content":[{"type":"output_text","text":"MARKER"}]}]}' > "$tmpdir/text-incomplete.json"
  expect_exit 0 "$0" < "$tmpdir/tool-pass.json"
  expect_exit 1 "$0" < "$tmpdir/tool-fail.json"
  expect_exit 0 "$0" --expect-text MARKER < "$tmpdir/text-pass.json"
  expect_exit 2 "$0" --expect-text MARKER < "$tmpdir/text-invalid.json"
  expect_exit 2 "$0" --expect-text MARKER < "$tmpdir/text-incomplete.json"
  echo '{"verdict":"pass","self_test":true}' | jq .
  exit 0
fi

VERDICT="$(verify)"
echo "$VERDICT" | jq .
case "$(echo "$VERDICT" | jq -r .verdict)" in
  pass) exit 0;;
  fail) exit 1;;
  *) exit 2;;
esac
