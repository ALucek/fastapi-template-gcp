#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env
ensure_command gcloud jq
require_env_vars PROJECT_ID

INPUT="${1:-}"
YES_FLAG="${2:-}"

if [ -z "$INPUT" ]; then
  echo "Usage: scripts/delete_api_key.sh <KEY_NAME or displayName> [--yes]" >&2
  exit 1
fi

# Resolve input to resource name (supports displayName)
if [[ "$INPUT" =~ ^projects/.*/locations/.*/keys/ ]]; then
  KEY_NAME="$INPUT"
else
  LIST_JSON="$(gcloud services api-keys list --project "$PROJECT_ID" --format=json || echo '[]')"
  KEY_NAME="$(jq -r --arg dn "$INPUT" '[.[] | select(.displayName == $dn)] | sort_by(.createTime) | last | .name // empty' <<<"$LIST_JSON")"
  if [ -z "$KEY_NAME" ]; then
    echo "Could not resolve key by displayName: $INPUT" >&2
    exit 1
  fi
fi

if [ "$YES_FLAG" != "--yes" ]; then
  read -r -p "Delete key $KEY_NAME ? (y/N) " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "Aborted"; exit 0 ;;
  esac
fi

gcloud services api-keys delete "$KEY_NAME" --project "$PROJECT_ID" --quiet
echo "Deleted: $KEY_NAME"


