#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: review-foundry-guide-feedback.sh --id <feedback-id> --output <private-json> [--environment <azd-env>]

Retrieves the exact managed Foundry input context and displayed answer for one
actionable feedback record. The output directory must be owned by the current user
and not group/world-writable. The output contains user content; keep it private and
delete it when the review is complete.
EOF
}

feedback_id=""
output_path=""
environment_name=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --id)
      feedback_id="${2:-}"
      shift 2
      ;;
    --output)
      output_path="${2:-}"
      shift 2
      ;;
    --environment)
      environment_name="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'." >&2
      usage >&2
      exit 1
      ;;
  esac
done

for command_name in az azd curl jq sha256sum base64 id stat; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: '$command_name' is required." >&2
    exit 1
  fi
done

if ! [[ "$feedback_id" =~ ^[0-9a-f]{32}$ ]]; then
  echo "Error: --id must be a 32-character lowercase hexadecimal feedback ID." >&2
  exit 1
fi

if [ -z "$output_path" ]; then
  echo "Error: --output is required." >&2
  exit 1
fi

if [ -e "$output_path" ] || [ -L "$output_path" ]; then
  echo "Error: output path already exists: $output_path" >&2
  exit 1
fi

output_dir="$(dirname "$output_path")"
if [ ! -d "$output_dir" ]; then
  echo "Error: output directory does not exist: $output_dir" >&2
  exit 1
fi

directory_permissions="$((8#$(stat -c '%a' "$output_dir")))"
directory_owner="$(stat -c '%u' "$output_dir")"
current_user="$(id -u)"
if [ "$directory_owner" != "$current_user" ] \
  || [ $((directory_permissions & 0022)) -ne 0 ]; then
  echo "Error: output directory must be owned by the current user without group/world write access." >&2
  exit 1
fi

if [ -n "$environment_name" ]; then
  environment_values="$(azd env get-values --environment "$environment_name")"
else
  environment_values="$(azd env get-values)"
fi
set -a
eval "$environment_values"
set +a

project_endpoint="${PROJECT_ENDPOINT:-}"
storage_name="${FOUNDRY_GUIDE_TOKEN_USAGE_STORAGE_NAME:-}"
table_name="FoundryGuideFeedback"

if [ -z "$project_endpoint" ] || [ -z "$storage_name" ] \
  || [ -z "${AZURE_SUBSCRIPTION_ID:-}" ] || [ -z "${AZURE_TENANT_ID:-}" ]; then
  echo "Error: PROJECT_ENDPOINT, FOUNDRY_GUIDE_TOKEN_USAGE_STORAGE_NAME, AZURE_SUBSCRIPTION_ID, and AZURE_TENANT_ID are required." >&2
  exit 1
fi

active_subscription="$(az account show --query id -o tsv | tr -d '\r\n')"
active_tenant="$(az account show --query tenantId -o tsv | tr -d '\r\n')"
if [ "$active_subscription" != "$AZURE_SUBSCRIPTION_ID" ]; then
  echo "Error: the active Azure subscription does not match the selected azd environment." >&2
  exit 1
fi
if [ "$active_tenant" != "$AZURE_TENANT_ID" ]; then
  echo "Error: the active Azure tenant does not match the selected azd environment." >&2
  exit 1
fi

umask 077
tmp_dir="$(mktemp -d --tmpdir="$output_dir" .foundry-guide-feedback-review.XXXXXX)"
output_tmp="$(mktemp --tmpdir="$output_dir" .foundry-guide-feedback-review.XXXXXX)"
cleanup() {
  rm -rf "$tmp_dir"
  rm -f "$output_tmp"
}
trap cleanup EXIT

record_file="$tmp_dir/record.json"
if ! az storage entity show \
  --auth-mode login \
  --account-name "$storage_name" \
  --table-name "$table_name" \
  --partition-key feedback \
  --row-key "$feedback_id" \
  -o json >"$record_file"; then
  echo "Error: feedback record was not found or the caller lacks Storage Table Data Reader on the feedback table." >&2
  exit 1
fi

required_properties=(
  ResponseId
  UserIsolationKey
  ChatIsolationKey
  InputSha256
  DisplayedTextSha256
  Reason
  AgentName
  AgentVersion
  ExpiresAt
)
for property in "${required_properties[@]}"; do
  if ! jq -e --arg property "$property" '.[$property] != null and (.[$property] | tostring | length > 0)' "$record_file" >/dev/null; then
    echo "Error: feedback record is missing required property '$property'." >&2
    exit 1
  fi
done

response_id="$(jq -r '.ResponseId' "$record_file")"
user_isolation_key="$(jq -r '.UserIsolationKey' "$record_file")"
chat_isolation_key="$(jq -r '.ChatIsolationKey' "$record_file")"
agent_name="$(jq -r '.AgentName' "$record_file")"

access_token="$(az account get-access-token \
  --resource https://ai.azure.com \
  --query accessToken \
  -o tsv | tr -d '\r\n')"
if [ -z "$access_token" ]; then
  echo "Error: could not acquire a Microsoft Foundry access token." >&2
  exit 1
fi

headers_file="$tmp_dir/headers"
printf '%s\n' \
  "Authorization: Bearer $access_token" \
  "x-ms-user-isolation-key: $user_isolation_key" \
  "x-ms-chat-isolation-key: $chat_isolation_key" \
  "Accept: application/json" >"$headers_file"

encoded_agent="$(jq -rn --arg value "$agent_name" '$value|@uri')"
base_url="${project_endpoint%/}/agents/${encoded_agent}/endpoint/protocols/openai/responses/${response_id}"
response_file="$tmp_dir/response.json"
input_items_file="$tmp_dir/input-items.json"

response_status="$(curl -sS \
  --header "@$headers_file" \
  --output "$response_file" \
  --write-out '%{http_code}' \
  "${base_url}?api-version=v1")"
input_items_status="$(curl -sS \
  --header "@$headers_file" \
  --output "$input_items_file" \
  --write-out '%{http_code}' \
  "${base_url}/input_items?api-version=v1")"

if [ "$response_status" != "200" ] || [ "$input_items_status" != "200" ]; then
  echo "Error: managed feedback evidence is unavailable (response HTTP $response_status, input items HTTP $input_items_status). The response may have expired or the caller may lack Foundry Agent Consumer." >&2
  exit 1
fi

displayed_text_file="$tmp_dir/displayed-text"
if jq -e '.output_text? | type == "string" and length > 0' "$response_file" >/dev/null; then
  jq -j '.output_text' "$response_file" >"$displayed_text_file"
else
  jq -j '
    [
      .. | objects
      | select(
          (.type? == "output_text" or .type? == "text")
          and (.text? | type == "string")
          and (.text | length > 0))
      | .text
    ]
    | reduce .[] as $text
        ([]; if index($text) then . else . + [$text] end)
    | join("\n")
  ' "$response_file" >"$displayed_text_file"
fi

conversation_file="$tmp_dir/conversation.json"
jq '
  [
    .data[]?
    | select(.role? == "user" or .role? == "assistant")
    | {
        role,
        text: (
          [
            .. | objects
            | select(
                (.type? == "input_text" or .type? == "output_text" or .type? == "text")
                and (.text? | type == "string"))
            | .text
          ]
          | join("\n")
        )
      }
    | select(.text | length > 0)
  ]
' "$input_items_file" >"$conversation_file"

expected_displayed_hash="$(jq -r '.DisplayedTextSha256' "$record_file")"
actual_displayed_hash="$(sha256sum "$displayed_text_file" | cut -d' ' -f1)"
if [ "$actual_displayed_hash" != "$expected_displayed_hash" ]; then
  echo "Error: retrieved response text does not match the text displayed by the application." >&2
  exit 1
fi

expected_input_hash="$(jq -r '.InputSha256' "$record_file")"
input_hash_found=false
while IFS= read -r encoded_text; do
  printf '%s' "$encoded_text" | base64 --decode >"$tmp_dir/input-candidate"
  if [ "$(sha256sum "$tmp_dir/input-candidate" | cut -d' ' -f1)" = "$expected_input_hash" ]; then
    input_hash_found=true
    break
  fi
done < <(jq -r '.[] | select(.role == "user") | .text | @base64' "$conversation_file")

if [ "$input_hash_found" != "true" ]; then
  echo "Error: the submitted question was not found in the retrieved response input items." >&2
  exit 1
fi

jq -n \
  --arg reason "$(jq -r '.Reason' "$record_file")" \
  --arg agentName "$(jq -r '.AgentName' "$record_file")" \
  --arg agentVersion "$(jq -r '.AgentVersion' "$record_file")" \
  --arg expiresAt "$(jq -r '.ExpiresAt' "$record_file")" \
  --rawfile displayedText "$displayed_text_file" \
  --slurpfile conversation "$conversation_file" \
  '{
    feedback: {
      reason: $reason,
      agentName: $agentName,
      agentVersion: $agentVersion,
      expiresAt: $expiresAt
    },
    conversation: $conversation[0],
    displayedAnswer: $displayedText,
    integrity: {
      submittedQuestionMatched: true,
      displayedAnswerMatched: true
    }
  }' >"$output_tmp"

chmod 600 "$output_tmp"
mv -n -- "$output_tmp" "$output_path"
if [ -e "$output_tmp" ]; then
  echo "Error: output path was created by another process: $output_path" >&2
  exit 1
fi
echo "Wrote private feedback review evidence to $output_path."
