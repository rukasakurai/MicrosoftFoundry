#!/usr/bin/env bash
# Classify raw Salesforce Hosted MCP Responses API evidence.
# Exit: 0=pass, 1=fail, 2=invalid/setup failure, 3=pre-T0 consent required.
set -euo pipefail

PHASE=""
EXPECTED_RECORD_ID=""
EXPECTED_RECORD_NAME="Contoso Refresh Probe"
readonly OAUTH_ERROR_PATTERN='401|403|unauthori[sz]ed|authentication|oauth|invalid[_ -]?(grant|client|scope|request|token)|unauthorized[_ -]?client|access[_ -]?denied|unsupported[_ -]?(grant[_ -]?type|response[_ -]?type)|token.*(invalid|expired|expiry)|consent'

usage() {
  cat <<'EOF'
Usage:
  verify-salesforce-mcp-refresh.sh --phase t0|t1 \
    --expected-record-id <synthetic-account-id> < response.json
  verify-salesforce-mcp-refresh.sh --self-test

T0 consent is setup_required, not a refresh failure. T1 consent or a targeted
OAuth/auth error is fail. Assistant prose without the exact tool evidence is invalid.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 2
}

classify() {
  local response matching_output expected_record_present=false
  response="$(cat)"
  matching_output="$(jq -r '
    def parsed_arguments:
      (.arguments // {}) as $arguments
      | if ($arguments | type) == "string"
        then (try ($arguments | fromjson) catch {})
        else $arguments
        end;
    "SELECT Id, Name FROM Account WHERE Name = '\''Contoso Refresh Probe'\'' ORDER BY Name LIMIT 1" as $query
    | .output[]?
    | select(.type == "mcp_call" and .name == "soqlQuery" and parsed_arguments == {q: $query})
    | .output? // empty
    | if type == "string" then . else tojson end
  ' <<<"$response")"
  if [ -n "$matching_output" ] &&
    printf '%s\n' "$matching_output" |
      jq -e -s --arg id "$EXPECTED_RECORD_ID" --arg name "$EXPECTED_RECORD_NAME" \
        '[.. | objects | select(.Id? == $id and .Name? == $name)] | length > 0' \
        >/dev/null 2>&1; then
    expected_record_present=true
  fi

  jq \
    --arg phase "$PHASE" \
    --arg auth_pattern "$OAUTH_ERROR_PATTERN" '
    def parsed_arguments:
      (.arguments // {}) as $arguments
      | if ($arguments | type) == "string"
        then (try ($arguments | fromjson) catch {})
        else $arguments
        end;
    def as_text: if type == "string" then . else tojson end;

    "SELECT Id, Name FROM Account WHERE Name = '\''Contoso Refresh Probe'\'' ORDER BY Name LIMIT 1" as $query
    | (.output // []) as $items
    | ($items | map(select(.type == "mcp_call"))) as $calls
    | ($calls | map(select(.name == "soqlQuery" and parsed_arguments == {q: $query}))) as $matching
    | ($matching | map(.output? | select(. != null))) as $outputs
    | ($matching | map(.error? | select(. != null) | as_text)) as $matching_errors
    | ([.error? | select(. != null) | as_text] | join("\n")) as $outer_error
    | ($matching_errors + ($outputs | map(as_text)) | join("\n")) as $matching_evidence
    | {
        phase: $phase,
        response_status: (.status // null),
        output_types: ($items | map(.type) | unique),
        tool_calls: ($calls | length),
        exact_query_calls: ($matching | length),
        exact_query_matched: (($calls | length) == 1 and ($matching | length) == 1),
        exact_query_tool_errors: ($matching_errors | length),
        tool_output_present: (($outputs | length) == 1),
        expected_record_present: $expected_record_present,
        consent_required: (($items | map(select(.type == "oauth_consent_request")) | length) > 0),
        auth_error_evidence: (
          (
            ($calls | length) == 0 and
            (
              (.error // null) != null and
              ($outer_error | test($auth_pattern; "i"))
            )
          ) or
          ($matching_evidence | test($auth_pattern; "i"))
        )
      }
    | . + {
        verdict:
          (if $phase == "t0" and .consent_required then "setup_required"
           elif $phase == "t0" and .auth_error_evidence then "setup_failed"
           elif $phase == "t1" and (.consent_required or .auth_error_evidence) then "fail"
           elif .response_status == "completed" and
                .exact_query_matched and
                .exact_query_tool_errors == 0 and
                .tool_output_present and
                .expected_record_present
           then "pass"
           else "invalid"
           end)
      }' --argjson expected_record_present "$expected_record_present" <<<"$response"
}

expect_verdict() {
  local expected="$1" phase="$2" file="$3"
  local actual
  PHASE="$phase"
  actual="$(classify < "$file" | jq -r '.verdict')"
  [ "$actual" = "$expected" ] ||
    die "self-test expected $expected, got $actual for $file"
}

self_test() {
  local tmp query
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" EXIT
  EXPECTED_RECORD_ID="001000000000001AAA"
  query="SELECT Id, Name FROM Account WHERE Name = 'Contoso Refresh Probe' ORDER BY Name LIMIT 1"

  jq -n --arg q "$query" --arg id "$EXPECTED_RECORD_ID" \
    '{status:"completed",output:[{type:"mcp_call",name:"soqlQuery",arguments:{q:$q},output:({records:[{Id:$id,Name:"Contoso Refresh Probe"}]}|tojson)}]}' \
    > "$tmp/pass.json"
  jq -n '{error:{type:"invalid_request_error",message:"401 Unauthorized: Invalid token"},output:[]}' \
    > "$tmp/fail.json"
  jq -n '{status:"completed",output:[{type:"oauth_consent_request",consent_link:"private"}]}' \
    > "$tmp/consent.json"
  jq -n --arg id "$EXPECTED_RECORD_ID" \
    '{status:"completed",output:[{type:"mcp_call",name:"soqlQuery",arguments:{q:"SELECT Id FROM Account LIMIT 1"},error:{message:"401 Invalid token"}}]}' \
    > "$tmp/wrong-query.json"
  jq -n --arg q "$query" \
    '{status:"completed",output:[{type:"mcp_call",name:"soqlQuery",arguments:{q:$q},error:{message:"401 Invalid token"}}]}' \
    > "$tmp/exact-query-error.json"
  jq -n --arg q "$query" --arg id "$EXPECTED_RECORD_ID" \
    '{status:"completed",output:[{type:"mcp_call",name:"soqlQuery",arguments:{q:$q},output:(({records:[]}|tojson)+"\n"+({records:[{Id:$id,Name:"Contoso Refresh Probe"}]}|tojson))}]}' \
    > "$tmp/multi-json.json"

  expect_verdict pass t0 "$tmp/pass.json"
  expect_verdict fail t1 "$tmp/fail.json"
  expect_verdict setup_required t0 "$tmp/consent.json"
  expect_verdict fail t1 "$tmp/consent.json"
  expect_verdict invalid t1 "$tmp/wrong-query.json"
  expect_verdict fail t1 "$tmp/exact-query-error.json"
  expect_verdict pass t0 "$tmp/multi-json.json"
  echo '{"verdict":"pass","self_test":true}' | jq .
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --phase) PHASE="${2:?missing value for --phase}"; shift 2 ;;
    --expected-record-id) EXPECTED_RECORD_ID="${2:?missing value for --expected-record-id}"; shift 2 ;;
    --self-test) self_test; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[ "$PHASE" = "t0" ] || [ "$PHASE" = "t1" ] || die "--phase must be t0 or t1"
[ -n "$EXPECTED_RECORD_ID" ] || die "--expected-record-id is required"

result="$(classify)"
echo "$result" | jq .
case "$(jq -r '.verdict' <<<"$result")" in
  pass) exit 0 ;;
  fail) exit 1 ;;
  setup_required) exit 3 ;;
  *) exit 2 ;;
esac
