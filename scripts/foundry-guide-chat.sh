#!/bin/bash
set -euo pipefail

required_azd_values=false
if [ -z "${PROJECT_ENDPOINT:-}" ]; then
  required_azd_values=true
fi
if [ -z "${APPLICATIONINSIGHTS_CONNECTION_STRING:-${APPLICATION_INSIGHTS_CONNECTION_STRING:-}}" ] \
  && { [ -z "${AZURE_RESOURCE_GROUP:-}" ] || [ -z "${APPLICATION_INSIGHTS_NAME:-}" ]; }; then
  required_azd_values=true
fi

load_agent_metadata=false
if [ -z "${FOUNDRY_GUIDE_AGENT_NAME:-}" ] || [ -z "${FOUNDRY_GUIDE_AGENT_VERSION:-}" ]; then
  load_agent_metadata=true
fi

if { [ "$required_azd_values" = true ] || [ "$load_agent_metadata" = true ]; } \
  && command -v azd >/dev/null 2>&1; then
  azd_environment=()
  if [ -n "${AZURE_ENV_NAME:-}" ]; then
    azd_environment=(--environment "$AZURE_ENV_NAME")
  fi

  if azd_values="$(azd env get-values "${azd_environment[@]}" 2>/dev/null)"; then
    declare -A explicit_values=()
    for name in \
      PROJECT_ENDPOINT APPLICATIONINSIGHTS_CONNECTION_STRING \
      APPLICATION_INSIGHTS_CONNECTION_STRING AZURE_RESOURCE_GROUP \
      APPLICATION_INSIGHTS_NAME FOUNDRY_GUIDE_AGENT_NAME \
      FOUNDRY_GUIDE_AGENT_VERSION
    do
      if [ -n "${!name:-}" ]; then
        explicit_values["$name"]="${!name}"
      fi
    done

    set -a
    eval "$azd_values"
    set +a

    for name in "${!explicit_values[@]}"; do
      export "$name=${explicit_values[$name]}"
    done
  elif [ "$required_azd_values" = true ]; then
    echo "Error: required values are missing and the azd environment could not be loaded." >&2
    exit 1
  fi
fi

if [ -z "${APPLICATIONINSIGHTS_CONNECTION_STRING:-}" ] \
  && [ -n "${APPLICATION_INSIGHTS_CONNECTION_STRING:-}" ]; then
  export APPLICATIONINSIGHTS_CONNECTION_STRING="$APPLICATION_INSIGHTS_CONNECTION_STRING"
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
