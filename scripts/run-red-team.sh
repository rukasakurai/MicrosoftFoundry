#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

environment_args=()
if [ "${1:-}" = "--environment" ]; then
  if [ -z "${2:-}" ]; then
    echo "Error: --environment requires an azd environment name." >&2
    exit 2
  fi
  environment_args=(--environment "$2")
  shift 2
fi

for command_name in az azd uv; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: '$command_name' is required." >&2
    exit 1
  fi
done

unset PROJECT_ENDPOINT AZURE_LOCATION AZURE_SUBSCRIPTION_ID AZURE_TENANT_ID
unset FOUNDRY_GUIDE_AGENT_NAME
if ! AZD_VALUES="$(azd env get-values "${environment_args[@]}")"; then
  echo "Error: unable to load the selected azd environment." >&2
  exit 1
fi
set -a
eval "$AZD_VALUES"
set +a

: "${PROJECT_ENDPOINT:?load the selected azd environment}"
: "${AZURE_LOCATION:?load the selected azd environment}"
: "${AZURE_SUBSCRIPTION_ID:?load the selected azd environment}"
: "${AZURE_TENANT_ID:?load the selected azd environment}"

clean() { printf '%s' "$1" | tr -d '\r\n'; }
AZURE_SUBSCRIPTION_ID="$(clean "$AZURE_SUBSCRIPTION_ID")"
AZURE_TENANT_ID="$(clean "$AZURE_TENANT_ID")"

az account set --subscription "$AZURE_SUBSCRIPTION_ID"
active_tenant="$(az account show --query tenantId -o tsv | tr -d '\r\n')"
if [ "$active_tenant" != "$AZURE_TENANT_ID" ]; then
  echo "Error: the active Azure tenant does not match the selected azd environment." >&2
  exit 1
fi

exec uv run \
  --project tests/red-team \
  --frozen \
  python tests/red-team/run.py "$@"
