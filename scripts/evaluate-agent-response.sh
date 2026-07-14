#!/usr/bin/env bash
# Generate one synthetic agent response and prove it receives an automated score.
set -euo pipefail

AGENT_NAME="evaluation-visibility-agent"
OUTPUT_PATH=""
TIMEOUT_SECONDS=600
POLL_SECONDS=10

usage() {
  cat <<'EOF'
Usage: evaluate-agent-response.sh [options]

Options:
  --agent-name NAME       Agent used for the synthetic response
  --output PATH           Write local correlation metadata as JSON; do not publish it
  --timeout-seconds N     Timeout for evaluation and telemetry ingestion (default: 600)
  --poll-seconds N        Evaluation polling interval (default: 10)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent-name) AGENT_NAME="${2:?missing value for --agent-name}"; shift 2;;
    --output) OUTPUT_PATH="${2:?missing value for --output}"; shift 2;;
    --timeout-seconds) TIMEOUT_SECONDS="${2:?missing value for --timeout-seconds}"; shift 2;;
    --poll-seconds) POLL_SECONDS="${2:?missing value for --poll-seconds}"; shift 2;;
    --help|-h) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2;;
  esac
done

for command_name in az azd curl jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: '$command_name' is required." >&2
    exit 1
  fi
done

if ! [[ "$AGENT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]]; then
  echo "Error: --agent-name must contain only letters, numbers, underscores, or hyphens." >&2
  exit 2
fi

for value_name in TIMEOUT_SECONDS POLL_SECONDS; do
  value="${!value_name}"
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: ${value_name} must be a positive integer." >&2
    exit 2
  fi
done

unset PROJECT_ENDPOINT MODEL_DEPLOYMENT_NAME AZURE_SUBSCRIPTION_ID AZURE_TENANT_ID
unset LOG_ANALYTICS_WORKSPACE_NAME
if ! AZD_VALUES="$(azd env get-values)"; then
  echo "Error: unable to load the selected azd environment." >&2
  exit 1
fi
set -a
eval "$AZD_VALUES"
set +a

: "${PROJECT_ENDPOINT:?load the selected azd environment}"
: "${MODEL_DEPLOYMENT_NAME:?load the selected azd environment}"
: "${AZURE_SUBSCRIPTION_ID:?load the selected azd environment}"
: "${AZURE_TENANT_ID:?load the selected azd environment}"
: "${LOG_ANALYTICS_WORKSPACE_NAME:?observability must be enabled}"

clean() { printf '%s' "$1" | tr -d '\r\n'; }
PROJECT_ENDPOINT="$(clean "$PROJECT_ENDPOINT")"
MODEL_DEPLOYMENT_NAME="$(clean "$MODEL_DEPLOYMENT_NAME")"
AZURE_SUBSCRIPTION_ID="$(clean "$AZURE_SUBSCRIPTION_ID")"
AZURE_TENANT_ID="$(clean "$AZURE_TENANT_ID")"

az account set --subscription "$AZURE_SUBSCRIPTION_ID"
active_tenant="$(az account show --query tenantId -o tsv | tr -d '\r\n')"
if [ "$active_tenant" != "$AZURE_TENANT_ID" ]; then
  echo "Error: the active Azure tenant does not match the selected azd environment." >&2
  exit 1
fi

endpoint="${PROJECT_ENDPOINT%/}"
token="$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)"
if [ -z "$token" ]; then
  echo "Error: failed to get an Azure token for https://ai.azure.com." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

request() {
  method="$1"
  url="$2"
  output_file="$3"
  data_file="${4:-}"

  if [ -n "$data_file" ]; then
    curl -sS -o "$output_file" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      --data @"$data_file" \
      "$url"
  else
    curl -sS -o "$output_file" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      "$url"
  fi
}

require_success() {
  action="$1"
  http_code="$2"
  if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
    echo "Error: failed to ${action} (HTTP ${http_code})." >&2
    exit 1
  fi
}

versions_code="$(
  request GET \
    "${endpoint}/agents/${AGENT_NAME}/versions?api-version=v1" \
    "$tmp_dir/versions.json"
)"
agent_version=""
if [ "$versions_code" -ge 200 ] && [ "$versions_code" -lt 300 ]; then
  agent_version="$(
    jq -r '
      (.value // .data // .items // .) as $items
      | if ($items | type) == "array" and ($items | length) > 0 then
          $items
          | sort_by((.version // "0") | tonumber? // 0)
          | last
          | .version // empty
        else
          empty
        end
    ' "$tmp_dir/versions.json"
  )"
elif [ "$versions_code" != "404" ]; then
  require_success "list agent versions" "$versions_code"
fi

if [ -z "$agent_version" ]; then
  jq -n --arg model "$MODEL_DEPLOYMENT_NAME" '{
    description: "Synthetic agent for evaluation visibility verification.",
    definition: {
      kind: "prompt",
      model: $model,
      instructions: "Follow the user instruction exactly. Use only synthetic data."
    }
  }' > "$tmp_dir/agent-request.json"

  agent_code="$(
    request POST \
      "${endpoint}/agents/${AGENT_NAME}/versions?api-version=v1" \
      "$tmp_dir/agent.json" \
      "$tmp_dir/agent-request.json"
  )"
  require_success "create the evaluation agent" "$agent_code"
  agent_version="$(jq -er '.version' "$tmp_dir/agent.json")"
fi

jq -n '{
  items: [{
    type: "message",
    role: "user",
    content: "This is synthetic evaluation traffic. Reply with exactly: EVALUATION_OK"
  }]
}' > "$tmp_dir/conversation-request.json"
conversation_code="$(
  request POST \
    "${endpoint}/conversations?api-version=v1" \
    "$tmp_dir/conversation.json" \
    "$tmp_dir/conversation-request.json"
)"
require_success "create the synthetic conversation" "$conversation_code"
conversation_id="$(jq -er '.id' "$tmp_dir/conversation.json")"

jq -n \
  --arg conversation "$conversation_id" \
  --arg name "$AGENT_NAME" \
  --arg version "$agent_version" '{
    conversation: $conversation,
    agent_reference: {
      type: "agent_reference",
      name: $name,
      version: $version
    }
  }' > "$tmp_dir/response-request.json"
response_code="$(
  request POST \
    "${endpoint}/openai/v1/responses" \
    "$tmp_dir/response.json" \
    "$tmp_dir/response-request.json"
)"
require_success "create the synthetic agent response" "$response_code"
response_id="$(jq -er '.id' "$tmp_dir/response.json")"
if ! jq -e '
  .status == "completed"
  and any(.. | objects; .type? == "output_text" and .text? == "EVALUATION_OK")
' "$tmp_dir/response.json" >/dev/null; then
  echo "Error: the synthetic response did not complete with the expected marker." >&2
  exit 1
fi

jq -n --arg model "$MODEL_DEPLOYMENT_NAME" '{
  name: "Response evaluation visibility",
  data_source_config: {
    type: "azure_ai_source",
    scenario: "responses"
  },
  testing_criteria: [{
    type: "azure_ai_evaluator",
    name: "coherence",
    evaluator_name: "builtin.coherence",
    initialization_parameters: {
      deployment_name: $model
    }
  }]
}' > "$tmp_dir/evaluation-request.json"
evaluation_code="$(
  request POST \
    "${endpoint}/openai/v1/evals" \
    "$tmp_dir/evaluation.json" \
    "$tmp_dir/evaluation-request.json"
)"
require_success "create the response evaluation" "$evaluation_code"
evaluation_id="$(jq -er '.id' "$tmp_dir/evaluation.json")"

jq -n --arg response_id "$response_id" '{
  name: "response-evaluation-visibility-run",
  data_source: {
    type: "azure_ai_responses",
    item_generation_params: {
      type: "response_retrieval",
      data_mapping: {
        response_id: "{{item.resp_id}}"
      },
      source: {
        type: "file_content",
        content: [{
          item: {
            resp_id: $response_id
          }
        }]
      }
    }
  }
}' > "$tmp_dir/run-request.json"
run_code="$(
  request POST \
    "${endpoint}/openai/v1/evals/${evaluation_id}/runs" \
    "$tmp_dir/run.json" \
    "$tmp_dir/run-request.json"
)"
require_success "start the response evaluation" "$run_code"
run_id="$(jq -er '.id' "$tmp_dir/run.json")"

deadline=$((SECONDS + TIMEOUT_SECONDS))
while true; do
  status_code="$(
    request GET \
      "${endpoint}/openai/v1/evals/${evaluation_id}/runs/${run_id}" \
      "$tmp_dir/run-status.json"
  )"
  require_success "read the response evaluation status" "$status_code"
  run_status="$(jq -r '.status // "unknown"' "$tmp_dir/run-status.json")"

  case "$run_status" in
    completed) break;;
    failed|canceled)
      jq -cn \
        --arg status "$run_status" '{
          classification: "evaluation_run_error",
          status: $status
        }'
      exit 1
      ;;
  esac

  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "Error: response evaluation did not complete within ${TIMEOUT_SECONDS} seconds." >&2
    exit 1
  fi
  sleep "$POLL_SECONDS"
done

output_code="$(
  request GET \
    "${endpoint}/openai/v1/evals/${evaluation_id}/runs/${run_id}/output_items" \
    "$tmp_dir/output-items.json"
)"
require_success "read the response evaluation output" "$output_code"

if ! jq -e '
  (.data | length) > 0
  and all(.data[]; .status == "completed")
' "$tmp_dir/output-items.json" >/dev/null; then
  echo '{"classification":"evaluator_error","error_type":"incomplete_output_item"}'
  exit 1
fi

jq '[
  .data[]?.results[]?
  | select(.score != null)
  | {
      metric: (.metric // .name),
      score,
      label,
      passed
    }
]' "$tmp_dir/output-items.json" > "$tmp_dir/metrics.json"

if ! jq -e 'length > 0 and all(.[]; (.score | type) == "number")' "$tmp_dir/metrics.json" >/dev/null; then
  jq -cn '{
    classification: "evaluator_error",
    error_type: "missing_score"
  }'
  exit 1
fi

jq -n \
  --arg response_id "$response_id" \
  --arg conversation_id "$conversation_id" \
  --arg agent_name "$AGENT_NAME" \
  --arg agent_version "$agent_version" \
  --arg evaluation_id "$evaluation_id" \
  --arg run_id "$run_id" \
  --slurpfile metrics "$tmp_dir/metrics.json" '{
    response_id: $response_id,
    conversation_id: $conversation_id,
    agent_name: $agent_name,
    agent_version: $agent_version,
    evaluation_id: $evaluation_id,
    run_id: $run_id,
    status: "completed",
    metrics: $metrics[0]
  }' > "$tmp_dir/correlation-result.json"

jq '{status, metrics}' "$tmp_dir/correlation-result.json"
if [ -n "$OUTPUT_PATH" ]; then
  cp "$tmp_dir/correlation-result.json" "$OUTPUT_PATH"
  echo "Wrote local correlation metadata to ${OUTPUT_PATH}; do not publish it." >&2
fi

"$(dirname "$0")/query-evaluation-result.sh" \
  --response-id "$response_id" \
  --wait-seconds "$TIMEOUT_SECONDS" \
  --poll-seconds "$POLL_SECONDS"
