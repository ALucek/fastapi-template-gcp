#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env
ensure_command gcloud jq
require_env_vars PROJECT_ID

echo -e "DISPLAY_NAME\tNAME\tCREATE_TIME\tRESTRICTED_SERVICES"

LIST_JSON="$(gcloud services api-keys list --project "$PROJECT_ID" --format=json || echo '[]')"
echo "$LIST_JSON" | jq -r '.[]?.name' | while read -r KEY_NAME; do
  [ -n "$KEY_NAME" ] || continue
  DESC="$(gcloud services api-keys describe "$KEY_NAME" --project "$PROJECT_ID" --format=json)"
  DN="$(jq -r '.displayName // ""' <<<"$DESC")"
  CT="$(jq -r '.createTime // ""' <<<"$DESC")"
  SRV="$(jq -r '.restrictions.apiTargets[]?.service | select(.)' <<<"$DESC" | paste -sd, -)"
  echo -e "${DN}\t${KEY_NAME}\t${CT}\t${SRV}"
done


