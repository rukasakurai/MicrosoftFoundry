#!/bin/bash
set -euo pipefail

for command_name in az gh jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: '$command_name' is required." >&2
    exit 1
  fi
done

AGENT_NAME="${FOUNDRY_GUIDE_AGENT_NAME:-foundry-guide}"
LOOKBACK="${FOUNDRY_GUIDE_FEEDBACK_LOOKBACK:-7d}"
MIN_NEGATIVE="${FOUNDRY_GUIDE_MIN_NEGATIVE_FEEDBACK:-3}"
TITLE="${FOUNDRY_GUIDE_FEEDBACK_ISSUE_TITLE:-Aggregate negative feedback for Foundry Guide}"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-${RESOURCE_GROUP:-}}"
APP_INSIGHTS_NAME="${APPLICATION_INSIGHTS_NAME:-}"
DRY_RUN="${FOUNDRY_GUIDE_FEEDBACK_DRY_RUN:-false}"

is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y) return 0 ;;
    *) return 1 ;;
  esac
}

if [ -z "$RESOURCE_GROUP" ] || [ -z "$APP_INSIGHTS_NAME" ]; then
  echo "Error: AZURE_RESOURCE_GROUP and APPLICATION_INSIGHTS_NAME are required." >&2
  exit 1
fi

if ! [[ "$MIN_NEGATIVE" =~ ^[0-9]+$ ]] || [ "$MIN_NEGATIVE" -lt 1 ]; then
  echo "Error: FOUNDRY_GUIDE_MIN_NEGATIVE_FEEDBACK must be a positive integer." >&2
  exit 1
fi

if ! [[ "$LOOKBACK" =~ ^[0-9]+[smhd]$ ]]; then
  echo "Error: FOUNDRY_GUIDE_FEEDBACK_LOOKBACK must use a simple duration such as 30m, 12h, or 7d." >&2
  exit 1
fi

AGENT_NAME_KQL="$(printf '%s' "$AGENT_NAME" | sed "s/'/''/g")"

workspace_id="$(az resource show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_INSIGHTS_NAME" \
  --resource-type Microsoft.Insights/components \
  --query properties.WorkspaceResourceId \
  -o tsv)"

app_insights_id="$(az resource show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$APP_INSIGHTS_NAME" \
  --resource-type Microsoft.Insights/components \
  --query id \
  -o tsv | tr -d '\r\n')"

if [ -z "$workspace_id" ]; then
  echo "Error: Application Insights workspace resource id was not found." >&2
  exit 1
fi

if [ -z "$app_insights_id" ]; then
  echo "Error: Application Insights resource id was not found." >&2
  exit 1
fi

workspace_customer_id="$(az monitor log-analytics workspace show --ids "$workspace_id" --query customerId -o tsv | tr -d '\r\n')"
if [ -z "$workspace_customer_id" ]; then
  echo "Error: Log Analytics workspace customer id was not found." >&2
  exit 1
fi

APP_INSIGHTS_ID_KQL="$(printf '%s' "$app_insights_id" | sed "s/'/''/g")"

query="$(cat <<KQL
let minNegative = ${MIN_NEGATIVE};
let appInsightsResourceId = tolower('${APP_INSIGHTS_ID_KQL}');
union isfuzzy=true customEvents, AppEvents, traces, AppTraces, dependencies, AppDependencies, requests, AppRequests
| extend eventTime = todatetime(coalesce(column_ifexists("timestamp", datetime(null)), column_ifexists("TimeGenerated", datetime(null))))
| where eventTime > ago(${LOOKBACK})
| extend resourceId = tolower(tostring(column_ifexists("_ResourceId", "")))
| where resourceId == appInsightsResourceId
| extend itemName = tostring(coalesce(column_ifexists("name", ""), column_ifexists("Name", "")))
| where itemName == "gen_ai.evaluation.result"
| extend dimensions = todynamic(column_ifexists("customDimensions", column_ifexists("Properties", dynamic({}))))
| extend agentName = tostring(dimensions["gen_ai.agent.name"])
| extend rating = todouble(dimensions["gen_ai.evaluation.score"])
| extend result = tostring(dimensions["gen_ai.evaluation.result"])
| where agentName == '${AGENT_NAME_KQL}'
| where result == "negative" or rating <= 2
| summarize negativeCount=count(), averageRating=avg(rating), firstSeen=min(eventTime), lastSeen=max(eventTime) by agentName
| where negativeCount >= minNegative
KQL
)"

response="$(az monitor log-analytics query \
  --workspace "$workspace_customer_id" \
  --analytics-query "$query" \
  -o json)"

row_count="$(jq -r 'if type == "array" then length else (.tables[0].rows | length // 0) end' <<<"$response")"
if [ "$row_count" -eq 0 ]; then
  echo "No aggregate negative feedback issue threshold met."
  exit 0
fi

if jq -e 'type == "array"' >/dev/null <<<"$response"; then
  negative_count="$(jq -r '.[0].negativeCount' <<<"$response")"
  average_rating="$(jq -r '.[0].averageRating' <<<"$response")"
  first_seen="$(jq -r '.[0].firstSeen' <<<"$response")"
  last_seen="$(jq -r '.[0].lastSeen' <<<"$response")"
else
  negative_count="$(jq -r '.tables[0].rows[0][1]' <<<"$response")"
  average_rating="$(jq -r '.tables[0].rows[0][2]' <<<"$response")"
  first_seen="$(jq -r '.tables[0].rows[0][3]' <<<"$response")"
  last_seen="$(jq -r '.tables[0].rows[0][4]' <<<"$response")"
fi

body="$(cat <<EOF
## Problem

Foundry Guide has received sustained aggregate negative feedback.

## Signal

| Metric | Value |
| --- | --- |
| Agent | ${AGENT_NAME} |
| Lookback | ${LOOKBACK} |
| Negative ratings | ${negative_count} |
| Average rating | ${average_rating} |
| First signal | ${first_seen} |
| Last signal | ${last_seen} |

## Constraints

This issue intentionally contains aggregate telemetry only. Do not add prompts, responses, feedback explanations, user identifiers, secrets, signed report URLs, or deployment-specific Azure identifiers.
EOF
)"

existing_number="$(gh issue list \
  --state open \
  --search "\"${TITLE}\" in:title" \
  --json number,title \
  --jq ".[] | select(.title == \"${TITLE}\") | .number" \
  | head -n 1)"

if [ -n "$existing_number" ]; then
  if is_true "$DRY_RUN"; then
    echo "Dry run: would update existing feedback issue #${existing_number}."
    exit 0
  fi

  gh issue comment "$existing_number" --body "$body" >/dev/null
  echo "Updated existing feedback issue #${existing_number}."
else
  if is_true "$DRY_RUN"; then
    echo "Dry run: would create feedback issue '${TITLE}'."
    exit 0
  fi

  gh issue create --title "$TITLE" --body "$body" >/dev/null
  echo "Created feedback issue: ${TITLE}"
fi
