#!/bin/bash
set -euo pipefail

is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|y) return 0 ;;
    *) return 1 ;;
  esac
}

if ! is_true "${ENABLE_TOKEN_USAGE_SAMPLE:-false}"; then
  echo "Token usage sample disabled. Set ENABLE_TOKEN_USAGE_SAMPLE=true to deploy it."
  exit 0
fi

for command_name in az dotnet zip curl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: '$command_name' is required." >&2
    exit 1
  fi
done

if [ -z "${AZURE_SUBSCRIPTION_ID:-}" ] \
  || [ -z "${AZURE_RESOURCE_GROUP:-}" ] \
  || [ -z "${API_MANAGEMENT_NAME:-}" ] \
  || [ -z "${APIM_GATEWAY_URL:-}" ] \
  || [ -z "${TOKEN_USAGE_API_NAME:-}" ] \
  || [ -z "${TOKEN_USAGE_SUBSCRIPTION_NAME:-}" ]; then
  echo "Error: token usage azd deployment outputs are required. Ensure ENABLE_TOKEN_USAGE_SAMPLE and ENABLE_OBSERVABILITY are true." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

dotnet publish \
  src/token-usage-api/TokenUsage.Api.csproj \
  --configuration Release \
  --output "$tmp_dir/publish" \
  --nologo

(
  cd "$tmp_dir/publish"
  zip -q -r "$tmp_dir/token-usage-api.zip" .
)

az webapp deploy \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$TOKEN_USAGE_API_NAME" \
  --src-path "$tmp_dir/token-usage-api.zip" \
  --type zip \
  --clean true \
  --restart true \
  --output none

subscription_key="$(az rest \
  --method post \
  --uri "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${API_MANAGEMENT_NAME}/subscriptions/${TOKEN_USAGE_SUBSCRIPTION_NAME}/listSecrets?api-version=2024-05-01" \
  --query primaryKey \
  --output tsv)"
if [ -z "$subscription_key" ]; then
  echo "Error: failed to retrieve the APIM test subscription key." >&2
  exit 1
fi

health_url="${APIM_GATEWAY_URL%/}/token-usage/health"
for attempt in $(seq 1 18); do
  if curl \
    --fail \
    --silent \
    --show-error \
    --max-time 10 \
    --header "Ocp-Apim-Subscription-Key: ${subscription_key}" \
    "$health_url" >/dev/null; then
    echo "Token usage API ready through APIM: ${APIM_GATEWAY_URL%/}/token-usage"
    exit 0
  fi

  if [ "$attempt" -lt 18 ]; then
    sleep 10
  fi
done

echo "Error: token usage API did not become healthy: ${health_url}" >&2
exit 1
