#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env
ensure_command gcloud jq
require_env_vars PROJECT_ID API_ID GATEWAY_ID

OLD_KEY=""
DELETE_OLD="0"
PRINT_KEY="0"

# Resolve an input (resource name or displayName) to a resource name
resolve_key_name() {
  local input="$1"
  if [[ "$input" =~ ^projects/.*/locations/.*/keys/ ]]; then
    echo "$input"
    return 0
  fi
  local list name
  list="$(gcloud services api-keys list --project "$PROJECT_ID" --format=json || echo '[]')"
  name="$(jq -r --arg dn "$input" '[.[] | select(.displayName == $dn)] | sort_by(.createTime) | last | .name // empty' <<<"$list")"
  if [ -z "$name" ]; then
    die "Could not resolve key by displayName: $input. Use full resource name or list keys with 'make keys'."
  fi
  echo "$name"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --old)
      OLD_KEY="$2"; shift 2 ;;
    --delete-old)
      DELETE_OLD="1"; shift ;;
    --print-key)
      PRINT_KEY="1"; shift ;;
    *)
      echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [ -n "$OLD_KEY" ]; then
  RESOLVED_OLD_KEY="$(resolve_key_name "$OLD_KEY")"
  echo "Old key resolved: $RESOLVED_OLD_KEY"
  OLD_KEY="$RESOLVED_OLD_KEY"
fi

MS="$(managed_service_name)"

# Create new key
DISPLAY_NAME="gw-rotate-$(timestamp)"
CREATE_OUT="$(gcloud services api-keys create \
  --display-name="$DISPLAY_NAME" \
  --project "$PROJECT_ID" --format=json)"

NEW_KEY_NAME="$(jq -r '.response.name // .name' <<<"$CREATE_OUT")"
NEW_KEY_STRING="$(jq -r '.response.keyString // .keyString // empty' <<<"$CREATE_OUT")"
[ -n "$NEW_KEY_NAME" ] || die "Failed to create API key"

# Restrict to managed service
gcloud services api-keys update "$NEW_KEY_NAME" \
  --api-target="service=${MS}" \
  --project "$PROJECT_ID" >/dev/null

if [ -n "$OLD_KEY" ]; then
  if [ "$DELETE_OLD" = "1" ]; then
    echo "Deleting old key: $OLD_KEY"
    gcloud services api-keys delete "$OLD_KEY" --project "$PROJECT_ID" --quiet
  else
    echo "Attempting to disable old key: $OLD_KEY"
    if ! gcloud services api-keys update "$OLD_KEY" --state=INACTIVE --project "$PROJECT_ID" >/dev/null 2>&1; then
      echo "Warning: disable not supported; leaving old key active. Consider --delete-old." >&2
    fi
  fi
fi

echo "Rotated API key"
echo "NEW_KEY_NAME=${NEW_KEY_NAME}"
echo "MANAGED_SERVICE=${MS}"

if [ "$PRINT_KEY" = "1" ] && [ -n "$NEW_KEY_STRING" ]; then
  echo "KEY=${NEW_KEY_STRING}"
fi


