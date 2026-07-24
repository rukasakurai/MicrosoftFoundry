#!/bin/bash
set -euo pipefail

simple_requests=3
parallel_requests=6
eventual_wait_seconds=900
output_file=""

usage() {
  cat <<'EOF'
Usage: ./scripts/test-token-usage-e2e.sh [options]

Options:
  --simple-requests N        Sequential requests through APIM-native quota (default: 3)
  --parallel-requests N      Concurrent authoritative requests (default: 6)
  --eventual-wait-seconds N  Maximum Log Analytics ingestion wait (default: 900)
  --output PATH              Write a sanitized JSON result
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --simple-requests)
      simple_requests="$2"
      shift 2
      ;;
    --parallel-requests)
      parallel_requests="$2"
      shift 2
      ;;
    --eventual-wait-seconds)
      eventual_wait_seconds="$2"
      shift 2
      ;;
    --output)
      output_file="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for value in "$simple_requests" "$parallel_requests" "$eventual_wait_seconds"; do
  case "$value" in
    ''|*[!0-9]*)
      echo "Error: numeric options must contain only nonnegative integers." >&2
      exit 1
      ;;
  esac
done

if [ "$simple_requests" -eq 0 ] || [ "$parallel_requests" -eq 0 ]; then
  echo "Error: request counts must be greater than zero." >&2
  exit 1
fi

for command_name in az azd curl jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: '$command_name' is required." >&2
    exit 1
  fi
done

env_json="$(azd env get-values --output json)"
env_value() {
  printf '%s' "$env_json" | jq -er --arg name "$1" '.[$name]'
}

azure_subscription_id="$(env_value AZURE_SUBSCRIPTION_ID)"
azure_tenant_id="$(env_value AZURE_TENANT_ID)"
azure_resource_group="$(env_value AZURE_RESOURCE_GROUP)"
api_management_name="$(env_value API_MANAGEMENT_NAME)"
apim_gateway_url="$(env_value APIM_GATEWAY_URL)"
token_usage_apim_api_name="$(env_value TOKEN_USAGE_APIM_API_NAME)"
strict_reservation_tokens="$(env_value TOKEN_USAGE_STRICT_RESERVATION_TOKENS)"

current_subscription_id="$(az account show --query id --output tsv)"
current_tenant_id="$(az account show --query tenantId --output tsv)"
if [ "$current_subscription_id" != "$azure_subscription_id" ] \
  || [ "$current_tenant_id" != "$azure_tenant_id" ]; then
  echo "Error: Azure CLI context does not match the selected azd environment." >&2
  echo "Expected subscription ${azure_subscription_id}, tenant ${azure_tenant_id}." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
test_subscription_name=""
test_subscription_uri=""
cleanup() {
  if [ -n "$test_subscription_uri" ]; then
    az rest \
      --method delete \
      --uri "${test_subscription_uri}?api-version=2024-05-01" \
      --output none >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

subscriptions_uri="https://management.azure.com/subscriptions/${azure_subscription_id}/resourceGroups/${azure_resource_group}/providers/Microsoft.ApiManagement/service/${api_management_name}/subscriptions"
api_scope="/subscriptions/${azure_subscription_id}/resourceGroups/${azure_resource_group}/providers/Microsoft.ApiManagement/service/${api_management_name}/apis/${token_usage_apim_api_name}"

test_subscription_name="token-usage-e2e-$(date -u +%Y%m%d%H%M%S)-${RANDOM}"
test_subscription_uri="${subscriptions_uri}/${test_subscription_name}"
test_subscription_body="$(jq -cn \
  --arg displayName "Token usage isolated E2E" \
  --arg scope "$api_scope" \
  '{properties:{displayName:$displayName,scope:$scope,state:"active"}}')"
az rest \
  --method put \
  --uri "${test_subscription_uri}?api-version=2024-05-01" \
  --headers "Content-Type=application/json" \
  --body "$test_subscription_body" \
  --output none

subscription_key="$(az rest \
  --method post \
  --uri "${test_subscription_uri}/listSecrets?api-version=2024-05-01" \
  --query primaryKey \
  --output tsv)"
if [ -z "$subscription_key" ]; then
  echo "Error: failed to retrieve the isolated APIM subscription key." >&2
  exit 1
fi

request_file="$tmp_dir/request.json"
jq -n '{
  messages: [
    {
      role: "user",
      content: "Reply with exactly the word OK."
    }
  ],
  max_completion_tokens: 16,
  stream: false
}' > "$request_file"

base_url="${apim_gateway_url%/}/token-usage"

health_ready=false
for attempt in $(seq 1 12); do
  status="$(curl \
    --silent \
    --show-error \
    --max-time 30 \
    --output "$tmp_dir/health.body" \
    --write-out '%{http_code}' \
    --header "Ocp-Apim-Subscription-Key: ${subscription_key}" \
    "${base_url}/health")"
  if [ "$status" -eq 200 ]; then
    health_ready=true
    break
  fi
  sleep 5
done
if [ "$health_ready" != true ]; then
  echo "Error: isolated APIM subscription did not become ready." >&2
  exit 1
fi

invoke_chat() {
  local approach="$1"
  local prefix="$2"
  curl \
    --silent \
    --show-error \
    --max-time 120 \
    --dump-header "${prefix}.headers" \
    --output "${prefix}.body" \
    --write-out '%{http_code}' \
    --header "Content-Type: application/json" \
    --header "Ocp-Apim-Subscription-Key: ${subscription_key}" \
    --data @"$request_file" \
    "${base_url}/${approach}/chat/completions"
}

invoke_usage() {
  local approach="$1"
  local output="$2"
  curl \
    --silent \
    --show-error \
    --max-time 30 \
    --output "$output" \
    --write-out '%{http_code}' \
    --header "Ocp-Apim-Subscription-Key: ${subscription_key}" \
    "${base_url}/${approach}/usage"
}

wait_for_usage_total() {
  local approach="$1"
  local minimum="$2"
  local output="$3"
  local deadline=$((SECONDS + eventual_wait_seconds))
  local status
  local reported=0

  while [ "$SECONDS" -le "$deadline" ]; do
    status="$(invoke_usage "$approach" "$output")"
    if [ "$status" -eq 200 ]; then
      reported="$(jq -er '.used | numbers' "$output")"
      if [ "$reported" -ge "$minimum" ]; then
        printf '%s\n' "$reported"
        return 0
      fi
    fi
    sleep 15
  done

  echo "Error: ${approach} usage did not reach ${minimum} tokens before timeout." >&2
  return 1
}

simple_usage_file="$tmp_dir/simple-usage.json"
simple_reported_before="$(wait_for_usage_total simple 0 "$simple_usage_file")"
apim_only_usage_file="$tmp_dir/apim-only-usage.json"
apim_only_reported_before="$(wait_for_usage_total apim-only 0 "$apim_only_usage_file")"

simple_measured_tokens=0
for index in $(seq 1 "$simple_requests"); do
  prefix="$tmp_dir/simple-${index}"
  status="$(invoke_chat simple "$prefix")"
  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "Error: simple request ${index} returned HTTP ${status}." >&2
    jq -c . "${prefix}.body" >&2 || true
    exit 1
  fi

  tokens="$(jq -er '.usage.total_tokens | numbers' "${prefix}.body")"
  simple_measured_tokens=$((simple_measured_tokens + tokens))
  if ! grep -qi '^X-Quota-Remaining:' "${prefix}.headers" \
    || ! grep -qi '^X-Quota-Charged-Tokens:' "${prefix}.headers"; then
    echo "Error: simple response omitted APIM quota headers." >&2
    exit 1
  fi
done

apim_only_measured_tokens=0
for index in $(seq 1 "$simple_requests"); do
  prefix="$tmp_dir/apim-only-${index}"
  status="$(invoke_chat apim-only "$prefix")"
  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "Error: APIM-only request ${index} returned HTTP ${status}." >&2
    jq -c . "${prefix}.body" >&2 || true
    exit 1
  fi

  tokens="$(jq -er '.usage.total_tokens | numbers' "${prefix}.body")"
  apim_only_measured_tokens=$((apim_only_measured_tokens + tokens))
  if ! grep -qi '^X-Quota-Remaining:' "${prefix}.headers" \
    || ! grep -qi '^X-Quota-Charged-Tokens:' "${prefix}.headers"; then
    echo "Error: APIM-only response omitted quota headers." >&2
    exit 1
  fi
done

strict_before_file="$tmp_dir/strict-before.json"
strict_before_status="$(invoke_usage strict "$strict_before_file")"
if [ "$strict_before_status" -ne 200 ]; then
  echo "Error: initial strict usage returned HTTP ${strict_before_status}." >&2
  exit 1
fi
strict_used_before="$(jq -er '.used | numbers' "$strict_before_file")"
strict_remaining_before="$(jq -er '.remaining | numbers' "$strict_before_file")"
if [ $((parallel_requests * strict_reservation_tokens)) -le "$strict_remaining_before" ]; then
  echo "Error: parallel load is too small to exercise authoritative quota rejection." >&2
  exit 1
fi

pids=""
for index in $(seq 1 "$parallel_requests"); do
  (
    invoke_chat strict "$tmp_dir/strict-${index}" > "$tmp_dir/strict-${index}.status"
  ) &
  pids="${pids} $!"
done

for pid in $pids; do
  wait "$pid"
done

strict_successes=0
strict_rejections=0
strict_measured_tokens=0
for index in $(seq 1 "$parallel_requests"); do
  status="$(cat "$tmp_dir/strict-${index}.status")"
  case "$status" in
    2??)
      strict_successes=$((strict_successes + 1))
      tokens="$(jq -er '.usage.total_tokens | numbers' "$tmp_dir/strict-${index}.body")"
      strict_measured_tokens=$((strict_measured_tokens + tokens))
      ;;
    403)
      strict_rejections=$((strict_rejections + 1))
      ;;
    *)
      echo "Error: strict request ${index} returned unexpected HTTP ${status}." >&2
      jq -c . "$tmp_dir/strict-${index}.body" >&2 || true
      exit 1
      ;;
  esac
done

if [ "$strict_successes" -eq 0 ] || [ "$strict_rejections" -eq 0 ]; then
  echo "Error: concurrent strict load must produce both successes and quota rejections." >&2
  exit 1
fi

strict_after_file="$tmp_dir/strict-after.json"
strict_after_status="$(invoke_usage strict "$strict_after_file")"
if [ "$strict_after_status" -ne 200 ]; then
  echo "Error: final strict usage returned HTTP ${strict_after_status}." >&2
  exit 1
fi
strict_used_after="$(jq -er '.used | numbers' "$strict_after_file")"
if [ "$strict_used_after" -ne $((strict_used_before + strict_measured_tokens)) ]; then
  echo "Error: authoritative ledger total does not equal measured successful usage." >&2
  exit 1
fi

simple_reported_tokens="$(wait_for_usage_total \
  simple \
  $((simple_reported_before + simple_measured_tokens)) \
  "$simple_usage_file")"
apim_only_reported_tokens="$(wait_for_usage_total \
  apim-only \
  $((apim_only_reported_before + apim_only_measured_tokens)) \
  "$apim_only_usage_file")"

simple_reported_delta=$((simple_reported_tokens - simple_reported_before))
if [ "$simple_reported_delta" -ne "$simple_measured_tokens" ]; then
  echo "Error: simple reported usage does not equal this run's measured usage." >&2
  exit 1
fi

apim_only_reported_delta=$((apim_only_reported_tokens - apim_only_reported_before))
if [ "$apim_only_reported_delta" -ne "$apim_only_measured_tokens" ]; then
  echo "Error: APIM-only reported usage does not equal this run's measured usage." >&2
  exit 1
fi

result="$(jq -n \
  --argjson simpleMeasured "$simple_measured_tokens" \
  --argjson simpleReported "$simple_reported_tokens" \
  --argjson simpleReportedBefore "$simple_reported_before" \
  --argjson apimOnlyMeasured "$apim_only_measured_tokens" \
  --argjson apimOnlyReported "$apim_only_reported_tokens" \
  --argjson apimOnlyReportedBefore "$apim_only_reported_before" \
  --argjson strictMeasured "$strict_measured_tokens" \
  --argjson strictReported "$strict_used_after" \
  --argjson strictSuccesses "$strict_successes" \
  --argjson strictRejections "$strict_rejections" \
  '{
    simple: {
      measuredTokensThisRun: $simpleMeasured,
      reportedTokensThisRun: ($simpleReported - $simpleReportedBefore),
      cumulativeReportedTokens: $simpleReported
    },
    apimOnly: {
      measuredTokensThisRun: $apimOnlyMeasured,
      reportedTokensThisRun: ($apimOnlyReported - $apimOnlyReportedBefore),
      cumulativeReportedTokens: $apimOnlyReported
    },
    strict: {
      measuredTokensThisRun: $strictMeasured,
      authoritativeUsedTokens: $strictReported,
      successfulRequests: $strictSuccesses,
      rejectedConcurrentRequests: $strictRejections
    }
  }')"

if [ -n "$output_file" ]; then
  printf '%s\n' "$result" > "$output_file"
fi
printf '%s\n' "$result"
