#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env
ensure_command gcloud jq
require_env_vars PROJECT_ID API_ID GATEWAY_ID

# Configure via env vars (no --flags)
# PRINT_KEY: set to 1 to print key string once
# KEY_PREFIX or PREFIX: display name prefix (default "gw")
PRINT_KEY="${PRINT_KEY:-0}"
NAME_PREFIX="${KEY_PREFIX:-${PREFIX:-gw}}"

MS="$(managed_service_name)"

# Enable the managed service in this project (idempotent)
gcloud services enable "$MS" --project "$PROJECT_ID" >/dev/null 2>&1 || true

DISPLAY_NAME="${NAME_PREFIX}-$(timestamp)"
CREATE_OUT="$(gcloud services api-keys create \
  --display-name="$DISPLAY_NAME" \
  --project "$PROJECT_ID" --format=json)"

KEY_NAME="$(jq -r '.response.name // .name' <<<"$CREATE_OUT")"
KEY_STRING="$(jq -r '.response.keyString // .keyString // empty' <<<"$CREATE_OUT")"

[ -n "$KEY_NAME" ] || die "Failed to create API key"

# Restrict the key to the Managed Service
gcloud services api-keys update "$KEY_NAME" \
  --api-target="service=${MS}" \
  --project "$PROJECT_ID" >/dev/null

echo "API key created and restricted to managed service"
echo "KEY_NAME=${KEY_NAME}"
echo "MANAGED_SERVICE=${MS}"

if [ "$PRINT_KEY" = "1" ] && [ -n "$KEY_STRING" ]; then
  echo "KEY=${KEY_STRING}"
fi


