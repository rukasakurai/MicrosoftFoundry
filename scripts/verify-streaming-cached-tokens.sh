#!/bin/bash
#
# Verify that cached_tokens is returned in streaming usage chunks via stream_options.
#
# This script sends two identical streaming Chat Completions requests to verify that:
# 1. The first request returns cached_tokens = 0 (no cache yet)
# 2. The second request returns cached_tokens > 0 (cache hit)
# Both requests use stream_options: {"include_usage": true} to receive a usage chunk.
#
# Prerequisites:
# - Azure CLI installed and authenticated (az login)
# - jq installed for JSON parsing
# - A model deployment (e.g., gpt-5.2) on Microsoft Foundry
#
# Usage:
#   # Using environment variables from azd
#   eval $(azd env get-values) && ./scripts/verify-streaming-cached-tokens.sh
#
#   # Or specify parameters explicitly
#   ./scripts/verify-streaming-cached-tokens.sh --endpoint <endpoint> --deployment <deployment-name>
#
# Environment Variables (from 'azd env get-values'):
#   COGNITIVE_SERVICES_ENDPOINT: Azure AI Services endpoint URL
#

set -e

# Default values
DEPLOYMENT_NAME=""
API_VERSION="2025-04-01-preview"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --endpoint)
      ENDPOINT="$2"
      shift 2
      ;;
    --deployment)
      DEPLOYMENT_NAME="$2"
      shift 2
      ;;
    --api-version)
      API_VERSION="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Verify cached_tokens in streaming Chat Completions usage chunks."
      echo ""
      echo "Options:"
      echo "  --endpoint <url>         Azure AI Services endpoint (default: from COGNITIVE_SERVICES_ENDPOINT env var)"
      echo "  --deployment <name>      Model deployment name (required, e.g., gpt-5.2)"
      echo "  --api-version <version>  API version (default: 2025-04-01-preview)"
      echo "  --help                   Show this help message"
      echo ""
      echo "Examples:"
      echo "  # Use environment variables from azd"
      echo "  eval \$(azd env get-values) && $0 --deployment gpt-5.2"
      echo ""
      echo "  # Specify endpoint explicitly"
      echo "  $0 --endpoint https://cog-abc123.cognitiveservices.azure.com --deployment gpt-5.2"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Validate jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required for JSON parsing. Install it with:"
  echo "  apt-get install jq   # Debian/Ubuntu"
  echo "  brew install jq      # macOS"
  exit 1
fi

# Get endpoint from environment if not provided
if [ -z "$ENDPOINT" ]; then
  ENDPOINT="${COGNITIVE_SERVICES_ENDPOINT}"
  if [ -z "$ENDPOINT" ]; then
    echo "Error: COGNITIVE_SERVICES_ENDPOINT environment variable not found."
    echo "Run 'eval \$(azd env get-values)' or provide --endpoint parameter."
    exit 1
  fi
fi

# Validate deployment name
if [ -z "$DEPLOYMENT_NAME" ]; then
  echo "Error: --deployment parameter is required (e.g., --deployment gpt-5.2)."
  exit 1
fi

# Remove trailing slash from endpoint if present
ENDPOINT="${ENDPOINT%/}"

# Construct Chat Completions API URL
API_URL="${ENDPOINT}/openai/deployments/${DEPLOYMENT_NAME}/chat/completions?api-version=${API_VERSION}"

echo "================================================================"
echo "Verifying cached_tokens in streaming usage chunks"
echo "================================================================"
echo ""
echo "  Endpoint:   ${ENDPOINT}"
echo "  Deployment: ${DEPLOYMENT_NAME}"
echo "  API Version: ${API_VERSION}"
echo ""

# Get Azure AD access token
echo "Obtaining Azure AD access token..."
ACCESS_TOKEN=$(az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv)

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Error: Failed to obtain access token. Please run 'az login' first."
  exit 1
fi

# Generate a long prompt (>= 1024 tokens) to meet prompt caching minimum.
# We repeat a deterministic paragraph to ensure identical content across requests.
LONG_PARAGRAPH="The quick brown fox jumps over the lazy dog. This is a test of the prompt caching mechanism in Azure OpenAI and Microsoft Foundry. We need to ensure that the prompt is long enough to meet the minimum token threshold for prompt caching to be triggered. Prompt caching is a feature that allows the API to cache the processing of long prompts so that subsequent requests with the same prefix can be served faster and at lower cost. The cache is based on exact token prefix matching, meaning the first N tokens must be identical for a cache hit to occur. This paragraph is being repeated multiple times to generate a prompt that exceeds 1024 tokens, which is the minimum threshold for prompt caching to activate. Each repetition adds approximately 120 tokens to the total prompt length, so we need at least 9 repetitions to exceed the threshold. The model will process the cached prefix more efficiently on the second request, and the usage object should reflect this with a non-zero cached_tokens value in the prompt_tokens_details field."

REPEATED_CONTENT=""
for i in $(seq 1 12); do
  REPEATED_CONTENT="${REPEATED_CONTENT} Repetition ${i}: ${LONG_PARAGRAPH}"
done

# Build the request body with stream_options
REQUEST_BODY=$(jq -n \
  --arg content "$REPEATED_CONTENT" \
  '{
    "messages": [
      {"role": "system", "content": "You are a helpful assistant. Respond briefly."},
      {"role": "user", "content": $content}
    ],
    "stream": true,
    "stream_options": {"include_usage": true},
    "max_tokens": 50
  }')

# Function to send a streaming request and extract the usage chunk
send_streaming_request() {
  local request_num=$1
  local raw_output
  local usage_chunk

  echo "--- Request ${request_num} ---"
  echo "Sending streaming Chat Completions request..."
  echo ""

  # Send the streaming request and capture SSE output
  raw_output=$(curl -s -N -X POST "${API_URL}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${REQUEST_BODY}" 2>&1)

  # Extract the usage chunk (the chunk with "usage" that is not null)
  # In SSE streaming, each chunk is prefixed with "data: "
  usage_chunk=$(echo "$raw_output" \
    | grep '^data: ' \
    | sed 's/^data: //' \
    | grep -v '^\[DONE\]$' \
    | while IFS= read -r line; do
        if echo "$line" | jq -e '.usage != null' 2>/dev/null > /dev/null; then
          echo "$line"
        fi
      done)

  if [ -z "$usage_chunk" ]; then
    echo "WARNING: No usage chunk found in streaming response."
    echo "Raw response (first 500 chars):"
    echo "$raw_output" | head -c 500
    echo ""
    echo ""
    return 1
  fi

  echo "Usage chunk (raw JSON):"
  echo "$usage_chunk" | jq '.usage'
  echo ""

  # Extract specific fields
  local prompt_tokens
  local completion_tokens
  local cached_tokens
  local has_prompt_details

  prompt_tokens=$(echo "$usage_chunk" | jq '.usage.prompt_tokens // empty')
  completion_tokens=$(echo "$usage_chunk" | jq '.usage.completion_tokens // empty')
  has_prompt_details=$(echo "$usage_chunk" | jq '.usage.prompt_tokens_details != null')
  cached_tokens=$(echo "$usage_chunk" | jq '.usage.prompt_tokens_details.cached_tokens // empty')

  echo "Results:"
  echo "  prompt_tokens:        ${prompt_tokens:-"(not present)"}"
  echo "  completion_tokens:    ${completion_tokens:-"(not present)"}"
  echo "  prompt_tokens_details present: ${has_prompt_details}"
  echo "  cached_tokens:        ${cached_tokens:-"(not present)"}"
  echo ""

  # Validate acceptance criteria
  if [ -z "$prompt_tokens" ] || [ "$prompt_tokens" = "null" ]; then
    echo "  ✗ FAIL: prompt_tokens is not populated"
  else
    echo "  ✓ PASS: prompt_tokens is populated (${prompt_tokens})"
  fi

  if [ -z "$completion_tokens" ] || [ "$completion_tokens" = "null" ]; then
    echo "  ✗ FAIL: completion_tokens is not populated"
  else
    echo "  ✓ PASS: completion_tokens is populated (${completion_tokens})"
  fi

  if [ "$has_prompt_details" != "true" ]; then
    echo "  ✗ FAIL: prompt_tokens_details is not present"
  else
    echo "  ✓ PASS: prompt_tokens_details is present"
  fi

  if [ "$request_num" -eq 1 ]; then
    if [ -n "$cached_tokens" ] && [ "$cached_tokens" != "null" ] && [ "$cached_tokens" -eq 0 ] 2>/dev/null; then
      echo "  ✓ PASS: cached_tokens is 0 (no cache on first request)"
    elif [ -z "$cached_tokens" ] || [ "$cached_tokens" = "null" ]; then
      echo "  ? INFO: cached_tokens not present on first request"
    else
      echo "  ? INFO: cached_tokens is ${cached_tokens} on first request (cache may already exist)"
    fi
  else
    if [ -n "$cached_tokens" ] && [ "$cached_tokens" != "null" ] && [ "$cached_tokens" -gt 0 ] 2>/dev/null; then
      echo "  ✓ PASS: cached_tokens is ${cached_tokens} (cache hit on second request)"
    elif [ -n "$cached_tokens" ] && [ "$cached_tokens" = "0" ]; then
      echo "  ✗ FAIL: cached_tokens is 0 (expected cache hit on second request)"
    else
      echo "  ? INFO: cached_tokens is ${cached_tokens:-"not present"}"
    fi
  fi

  echo ""
}

# Send first request (should have cached_tokens = 0)
echo ""
send_streaming_request 1

# Brief pause to allow cache to be established
echo "Waiting 3 seconds for cache to be established..."
sleep 3
echo ""

# Send second request (should have cached_tokens > 0)
send_streaming_request 2

echo "================================================================"
echo "Verification complete."
echo "================================================================"
echo ""
echo "Report:"
echo "  Model deployment: ${DEPLOYMENT_NAME}"
echo "  API version:      ${API_VERSION}"
echo "  Endpoint:         ${ENDPOINT}"
echo ""
echo "See docs/streaming-cached-tokens.md for more information."
