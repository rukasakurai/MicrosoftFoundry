#!/usr/bin/env bash
# Classify a response-correlated evaluation event without printing its content.
set -euo pipefail

RESPONSE_ID=""
SINCE="30m"
WAIT_SECONDS=0
POLL_SECONDS=15

usage() {
  cat <<'EOF'
Usage: query-evaluation-result.sh --response-id ID [options]

Options:
  --response-id ID       Foundry response ID to inspect
  --since DURATION       KQL lookback such as 30m, 2h, or 1d (default: 30m)
  --wait-seconds NUMBER  Wait for telemetry ingestion (default: 0)
  --poll-seconds NUMBER  Poll interval while waiting (default: 15)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --response-id) RESPONSE_ID="${2:?missing value for --response-id}"; shift 2;;
    --since) SINCE="${2:?missing value for --since}"; shift 2;;
    --wait-seconds) WAIT_SECONDS="${2:?missing value for --wait-seconds}"; shift 2;;
    --poll-seconds) POLL_SECONDS="${2:?missing value for --poll-seconds}"; shift 2;;
    --help|-h) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2;;
  esac
done

for command_name in az azd jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: '$command_name' is required." >&2
    exit 1
  fi
done

if ! [[ "$RESPONSE_ID" =~ ^resp_[A-Za-z0-9]+$ ]]; then
  echo "Error: --response-id must be a Foundry response ID." >&2
  exit 2
fi

if ! [[ "$SINCE" =~ ^[1-9][0-9]*[mhd]$ ]]; then
  echo "Error: --since must be a positive KQL duration such as 30m, 2h, or 1d." >&2
  exit 2
fi

for value_name in WAIT_SECONDS POLL_SECONDS; do
  value="${!value_name}"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "Error: ${value_name} must be a nonnegative integer." >&2
    exit 2
  fi
done

if [ "$POLL_SECONDS" -lt 1 ]; then
  echo "Error: POLL_SECONDS must be at least 1." >&2
  exit 2
fi

unset AZURE_SUBSCRIPTION_ID AZURE_TENANT_ID AZURE_RESOURCE_GROUP
unset LOG_ANALYTICS_WORKSPACE_NAME
if ! AZD_VALUES="$(azd env get-values)"; then
  echo "Error: unable to load the selected azd environment." >&2
  exit 1
fi
set -a
eval "$AZD_VALUES"
set +a

: "${AZURE_SUBSCRIPTION_ID:?load the selected azd environment}"
: "${AZURE_TENANT_ID:?load the selected azd environment}"
: "${AZURE_RESOURCE_GROUP:?load the selected azd environment}"
: "${LOG_ANALYTICS_WORKSPACE_NAME:?observability must be enabled}"

clean() { printf '%s' "$1" | tr -d '\r\n'; }
AZURE_SUBSCRIPTION_ID="$(clean "$AZURE_SUBSCRIPTION_ID")"
AZURE_TENANT_ID="$(clean "$AZURE_TENANT_ID")"
AZURE_RESOURCE_GROUP="$(clean "$AZURE_RESOURCE_GROUP")"
LOG_ANALYTICS_WORKSPACE_NAME="$(clean "$LOG_ANALYTICS_WORKSPACE_NAME")"

az account set --subscription "$AZURE_SUBSCRIPTION_ID"
active_tenant="$(az account show --query tenantId -o tsv | tr -d '\r\n')"
if [ "$active_tenant" != "$AZURE_TENANT_ID" ]; then
  echo "Error: the active Azure tenant does not match the selected azd environment." >&2
  exit 1
fi

workspace_id="$(
  az monitor log-analytics workspace show \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --workspace-name "$LOG_ANALYTICS_WORKSPACE_NAME" \
    --query customerId -o tsv | tr -d '\r\n'
)"
if [ -z "$workspace_id" ]; then
  echo "Error: the selected environment has no queryable Log Analytics workspace." >&2
  exit 1
fi

query="
union isfuzzy=true AppEvents, (datatable(TimeGenerated:datetime, Name:string, Properties:dynamic)[])
| where TimeGenerated > ago(${SINCE})
| where Name == 'gen_ai.evaluation.result'
| extend
    response_id=tostring(Properties['gen_ai.response.id']),
    metric=tostring(Properties['gen_ai.evaluation.name']),
    score=coalesce(
      todouble(Properties['gen_ai.evaluation.score.value']),
      todouble(Properties['gen_ai.evaluation.score'])
    ),
    label=tostring(Properties['gen_ai.evaluation.score.label']),
    error_type=tostring(Properties['error.type']),
    source=tostring(Properties['microsoft.gen_ai.human_evaluation.source']),
    actor_type=tostring(Properties['microsoft.gen_ai.evaluation.actor.type'])
| where response_id == '${RESPONSE_ID}'
| project TimeGenerated, metric, score, label, error_type, source, actor_type
| order by TimeGenerated desc
"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

deadline=$((SECONDS + WAIT_SECONDS))
while true; do
  if ! az monitor log-analytics query \
    --workspace "$workspace_id" \
    --analytics-query "$query" \
    -o json > "$tmp_dir/result.json" 2> "$tmp_dir/query-error.txt"; then
    if [ "$SECONDS" -lt "$deadline" ]; then
      sleep "$POLL_SECONDS"
      continue
    fi
    echo '{"classification":"connection_or_permission_error"}'
    echo "Error: Azure Monitor query failed. Verify the selected environment and Log Analytics Reader access." >&2
    exit 1
  fi

  if ! jq -e 'type == "array"' "$tmp_dir/result.json" >/dev/null; then
    echo '{"classification":"connection_or_permission_error"}'
    echo "Error: Azure Monitor returned an unexpected result shape." >&2
    exit 1
  fi

  scored="$(
    jq -c '
      first(
        .[]
        | select((.source // "") == "" and (.actor_type // "") != "human")
        | select((.score | tonumber?) != null and (.error_type // "") == "")
        | {
            classification: "scored_automated_evaluation",
            metric,
            score: (.score | tonumber),
            label
          }
      ) // empty
    ' "$tmp_dir/result.json"
  )"
  if [ -n "$scored" ]; then
    printf '%s\n' "$scored"
    exit 0
  fi

  evaluator_error="$(
    jq -c '
      first(
        .[]
        | select((.source // "") == "" and (.actor_type // "") != "human")
        | {
            classification: "evaluator_error",
            metric,
            error_type: (
              if (.error_type // "") == "" then "missing_score" else .error_type end
            )
          }
      ) // empty
    ' "$tmp_dir/result.json"
  )"
  if [ -n "$evaluator_error" ]; then
    printf '%s\n' "$evaluator_error"
    exit 1
  fi

  human_only="$(
    jq -c '
      [
        .[]
        | if (.source // "") == "end_user" then
            "end_user"
          elif (.source // "") == "builder" or (.actor_type // "") == "human" then
            "builder"
          else
            empty
          end
      ]
      | unique
      | if length > 0 then
          {
            classification: "human_feedback_only",
            sources: .
          }
        else
          empty
        end
    ' "$tmp_dir/result.json"
  )"
  if [ "$SECONDS" -ge "$deadline" ]; then
    if [ -n "$human_only" ]; then
      printf '%s\n' "$human_only"
      exit 1
    fi
    echo '{"classification":"missing_evaluation_event"}'
    exit 1
  fi

  sleep "$POLL_SECONDS"
done
