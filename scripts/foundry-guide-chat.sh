#!/bin/bash
set -euo pipefail

if command -v azd >/dev/null 2>&1; then
  set -a
  eval "$(azd env get-values)"
  set +a
fi

if [ -z "${APPLICATIONINSIGHTS_CONNECTION_STRING:-}" ]; then
  if [ -z "${AZURE_RESOURCE_GROUP:-}" ] || [ -z "${APPLICATION_INSIGHTS_NAME:-}" ]; then
    echo "Error: APPLICATIONINSIGHTS_CONNECTION_STRING is not set, and AZURE_RESOURCE_GROUP/APPLICATION_INSIGHTS_NAME are unavailable." >&2
    exit 1
  fi

  APPLICATIONINSIGHTS_CONNECTION_STRING="$(az resource show \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$APPLICATION_INSIGHTS_NAME" \
    --resource-type Microsoft.Insights/components \
    --query properties.ConnectionString \
    -o tsv)"
  export APPLICATIONINSIGHTS_CONNECTION_STRING
fi

dotnet run --project scripts/dotnet/FoundryGuideFeedback -- "$@"
