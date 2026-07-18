#!/bin/bash
set -euo pipefail

is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y) return 0 ;;
    *) return 1 ;;
  esac
}

if ! is_true "${ENABLE_FOUNDRY_GUIDE:-false}"; then
  echo "Foundry Guide deployment disabled. Set ENABLE_FOUNDRY_GUIDE=true to create the sample agent."
  exit 0
fi

for command_name in az curl jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: '$command_name' is required." >&2
    exit 1
  fi
done

PROJECT_ENDPOINT="${PROJECT_ENDPOINT:-}"
MODEL_ID="${FOUNDRY_GUIDE_MODEL_DEPLOYMENT_NAME:-${MODEL_DEPLOYMENT_NAME:-gpt-5.4}}"
AGENT_NAME="${FOUNDRY_GUIDE_AGENT_NAME:-foundry-guide}"
AGENT_DESCRIPTION="${FOUNDRY_GUIDE_AGENT_DESCRIPTION:-Foundry Guide assistant for the feedback-loop sample}"
INSTRUCTIONS_FILE="${FOUNDRY_GUIDE_INSTRUCTIONS_FILE:-scripts/foundry-guide-instructions.md}"
FORCE_NEW_VERSION="${FOUNDRY_GUIDE_FORCE_NEW_VERSION:-false}"

if [ -z "$PROJECT_ENDPOINT" ]; then
  echo "Error: PROJECT_ENDPOINT is required. Run 'azd provision' first or load azd env values." >&2
  exit 1
fi

if [ ! -f "$INSTRUCTIONS_FILE" ]; then
  echo "Error: instructions file not found: $INSTRUCTIONS_FILE" >&2
  exit 1
fi

PROJECT_ENDPOINT="${PROJECT_ENDPOINT%/}"
ACCESS_TOKEN="$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)"
if [ -z "$ACCESS_TOKEN" ]; then
  echo "Error: failed to get an Azure token for https://ai.azure.com." >&2
  exit 1
fi

request_with_retry() {
  local method="$1"
  local url="$2"
  local output_file="$3"
  local data_file="${4:-}"
  local content_type="application/json"
  local http_code="000"
  local attempt

  if [ "$method" = "PATCH" ]; then
    content_type="application/merge-patch+json"
  fi

  for attempt in $(seq 1 12); do
    if [ -n "$data_file" ]; then
      http_code="$(curl -sS -o "$output_file" -w '%{http_code}' \
        -X "$method" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: ${content_type}" \
        --data @"$data_file" \
        "$url" || printf '000')"
    else
      http_code="$(curl -sS -o "$output_file" -w '%{http_code}' \
        -X "$method" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: ${content_type}" \
        "$url" || printf '000')"
    fi

    case "$http_code" in
      401|403|429|5??|000)
        if [ "$attempt" -lt 12 ]; then
          echo "Foundry API returned HTTP ${http_code}; retrying after RBAC/API propagation (${attempt}/12)..." >&2
          sleep 10
          continue
        fi
        ;;
    esac

    printf '%s' "$http_code"
    return 0
  done
}

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

versions_body="$tmp_dir/versions.json"
versions_code="$(request_with_retry GET "${PROJECT_ENDPOINT}/agents/${AGENT_NAME}/versions?api-version=v1" "$versions_body")"

latest_version=""
if [ "$versions_code" -ge 200 ] && [ "$versions_code" -lt 300 ]; then
  latest_version="$(jq -r '
    (.value // .data // .items // .) as $items
    | if ($items | type) == "array" and ($items | length) > 0 then
        $items
        | sort_by((.version // "0") | tonumber? // 0)
        | last
        | .version // empty
      else
        empty
      end
  ' "$versions_body")"
fi

if [ -n "$latest_version" ] && ! is_true "$FORCE_NEW_VERSION"; then
  echo "Foundry Guide agent '${AGENT_NAME}:${latest_version}' already exists."
else
  instructions="$(cat "$INSTRUCTIONS_FILE")"
  request_body="$tmp_dir/request.json"
  jq -n \
    --arg description "$AGENT_DESCRIPTION" \
    --arg model "$MODEL_ID" \
    --arg instructions "$instructions" \
    '{
      description: $description,
      definition: {
        kind: "prompt",
        model: $model,
        instructions: $instructions
      }
    }' > "$request_body"

  response_body="$tmp_dir/create-response.json"
  create_code="$(request_with_retry POST "${PROJECT_ENDPOINT}/agents/${AGENT_NAME}/versions?api-version=v1" "$response_body" "$request_body")"

  if [ "$create_code" -lt 200 ] || [ "$create_code" -ge 300 ]; then
    echo "Error: failed to create Foundry Guide agent (HTTP ${create_code})." >&2
    cat "$response_body" >&2
    exit 1
  fi

  latest_version="$(jq -r '.version // empty' "$response_body")"
  if [ -z "$latest_version" ]; then
    echo "Error: agent creation response did not include a version." >&2
    cat "$response_body" >&2
    exit 1
  fi

  echo "Created Foundry Guide agent '${AGENT_NAME}:${latest_version}'."
fi

if is_true "${ENABLE_FOUNDRY_GUIDE_WEB_APP:-false}"; then
  endpoint_body="$tmp_dir/endpoint.json"
  jq -n '{
    agent_endpoint: {
      authorization_schemes: [
        {
          type: "Entra",
          isolation_key_source: {
            kind: "Header"
          }
        }
      ]
    }
  }' > "$endpoint_body"

  endpoint_response="$tmp_dir/endpoint-response.json"
  endpoint_code="$(request_with_retry PATCH "${PROJECT_ENDPOINT}/agents/${AGENT_NAME}?api-version=v1" "$endpoint_response" "$endpoint_body")"
  if [ "$endpoint_code" -lt 200 ] || [ "$endpoint_code" -ge 300 ]; then
    echo "Error: failed to configure Foundry Guide endpoint isolation (HTTP ${endpoint_code})." >&2
    cat "$endpoint_response" >&2
    exit 1
  fi
fi

if command -v azd >/dev/null 2>&1 && [ -n "${AZURE_ENV_NAME:-}" ]; then
  azd env set --environment "$AZURE_ENV_NAME" FOUNDRY_GUIDE_AGENT_NAME "$AGENT_NAME" >/dev/null
  azd env set --environment "$AZURE_ENV_NAME" FOUNDRY_GUIDE_AGENT_VERSION "$latest_version" >/dev/null
fi

echo "Foundry Guide agent ready: ${AGENT_NAME}:${latest_version}"
