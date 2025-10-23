#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env
ensure_command gcloud sed mktemp
require_env_vars PROJECT_ID REGION API_ID GATEWAY_ID OPENAPI_SPEC SERVICE

if [ -z "${GATEWAY_SA:-}" ]; then
  GATEWAY_SA="apigw-invoker@${PROJECT_ID}.iam.gserviceaccount.com"
fi

URL="$(cloud_run_url)"

RENDERED_DIR="$(mktemp -d /tmp/openapi.rendered.XXXXXX)"
RENDERED="$RENDERED_DIR/openapi.rendered.yaml"
trap 'rm -rf "$RENDERED_DIR"' EXIT

if [ ! -f "$OPENAPI_SPEC" ]; then
  echo "OpenAPI spec file not found: $OPENAPI_SPEC" >&2
  exit 1
fi

sed "s#https://YOUR_CLOUD_RUN_URL#${URL}#g" "$OPENAPI_SPEC" > "$RENDERED"

# Create API (idempotent)
gcloud api-gateway apis create "$API_ID" --project "$PROJECT_ID" >/dev/null 2>&1 || true

CFG_ID="fastapi-config-$(timestamp)"

echo "Creating API config: $CFG_ID"
gcloud api-gateway api-configs create "$CFG_ID" \
  --api="$API_ID" \
  --openapi-spec="$RENDERED" \
  --backend-auth-service-account="$GATEWAY_SA" \
  --project="$PROJECT_ID"

echo "Creating/updating gateway: $GATEWAY_ID"
gcloud api-gateway gateways create "$GATEWAY_ID" \
  --api="$API_ID" --api-config="$CFG_ID" \
  --location="$REGION" --project "$PROJECT_ID" >/dev/null 2>&1 || true

gcloud api-gateway gateways update "$GATEWAY_ID" \
  --api="$API_ID" --api-config="$CFG_ID" \
  --location="$REGION" --project "$PROJECT_ID"

HOST="$(gcloud api-gateway gateways describe "$GATEWAY_ID" \
  --location "$REGION" --project "$PROJECT_ID" \
  --format='value(defaultHostname)')"

echo "Gateway Hostname: https://${HOST}"

CURRENT_CFG_PATH="$(gcloud api-gateway gateways describe "$GATEWAY_ID" \
  --location "$REGION" --project "$PROJECT_ID" \
  --format='value(apiConfig)')"
CURRENT_CFG="${CURRENT_CFG_PATH##*/}"

KEEP_RECENT_CONFIGS="${KEEP_RECENT_CONFIGS:-3}"

echo "Cleaning up stale API configs (keeping ${KEEP_RECENT_CONFIGS})"
mapfile -t CONFIG_PATHS < <(gcloud api-gateway api-configs list \
  --api="$API_ID" --project="$PROJECT_ID" \
  --sort-by=~createTime --format='value(name)')

KEPT=0
for CONFIG_PATH in "${CONFIG_PATHS[@]}"; do
  [[ -n "$CONFIG_PATH" ]] || continue

  CONFIG_NAME="${CONFIG_PATH##*/}"

  if [[ "$CONFIG_NAME" == "$CURRENT_CFG" ]]; then
    ((KEPT++))
    continue
  fi

  if (( KEPT < KEEP_RECENT_CONFIGS )); then
    ((KEPT++))
    continue
  fi

  echo "Deleting stale API config: ${CONFIG_NAME}"
  gcloud api-gateway api-configs delete "$CONFIG_NAME" \
    --api="$API_ID" --project="$PROJECT_ID" --quiet || \
    echo "Warning: Failed to delete API config ${CONFIG_NAME}"
done


