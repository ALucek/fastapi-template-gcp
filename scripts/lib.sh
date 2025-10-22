#!/usr/bin/env bash

# Shared helpers for automation scripts

die() {
  echo "[error] $*" >&2
  exit 1
}

ensure_command() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
  done
}

require_env_vars() {
  local var_name
  for var_name in "$@"; do
    if [ -z "${!var_name:-}" ]; then
      die "Missing required variable: $var_name (define it in .env)"
    fi
  done
}

script_dir() {
  local src
  src="${BASH_SOURCE[0]}"
  while [ -h "$src" ]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  cd -P "$(dirname "$src")" && pwd
}

repo_root() {
  local dir
  dir="$(script_dir)"
  cd "$dir/.." && pwd
}

load_env() {
  local root
  root="$(repo_root)"
  local files loaded caller
  loaded=0
  files="${ENV_FILES:-}"
  if [ -z "$files" ]; then
    # Choose sensible defaults based on the caller script name
    caller="$(basename "${BASH_SOURCE[1]:-$0}")"
    case "$caller" in
      dev_uvicorn.sh)
        files=".env.infra:.env.app"
        ;;
      build_and_deploy.sh)
        files=".env.infra:.env.deploy.${DEPLOY_ENV:-dev}"
        ;;
      update_gateway.sh|doctor.sh|init_project.sh|create_api_key.sh|rotate_api_key.sh|list_api_keys.sh|delete_api_key.sh)
        files=".env.infra"
        ;;
      *)
        files=".env.infra"
        ;;
    esac
  fi

  IFS=':' read -r -a arr <<< "$files"
  set -a
  for f in "${arr[@]}"; do
    if [ -f "$root/$f" ]; then
      # shellcheck disable=SC1090
      . "$root/$f"
      loaded=1
    fi
  done
  set +a

  # Backward compatibility: fall back to legacy .env if nothing loaded
  if [ "$loaded" = "0" ] && [ -f "$root/.env" ]; then
    # shellcheck disable=SC1090
    set -a; . "$root/.env"; set +a
    loaded=1
  fi

  if [ "$loaded" = "0" ]; then
    die "No env files loaded. Run: make env-examples and edit .env.* files"
  fi
}

timestamp() {
  date +%Y%m%d-%H%M%S
}

cloud_run_url() {
  require_env_vars PROJECT_ID REGION SERVICE
  ensure_command gcloud
  local url
  url="$(gcloud run services describe "$SERVICE" \
    --region "$REGION" --project "$PROJECT_ID" \
    --format='value(status.url)')"
  [ -n "$url" ] || die "Could not resolve Cloud Run URL for service $SERVICE"
  echo "$url"
}

managed_service_name() {
  require_env_vars PROJECT_ID REGION API_ID GATEWAY_ID
  ensure_command gcloud
  local cfg ms
  cfg="$(gcloud api-gateway gateways describe "$GATEWAY_ID" \
    --location "$REGION" --project "$PROJECT_ID" \
    --format='value(apiConfig)' 2>/dev/null || true)"

  if [ -n "$cfg" ]; then
    ms="$(gcloud api-gateway api-configs describe "$cfg" \
      --api="$API_ID" --project="$PROJECT_ID" \
      --format='value(googleServiceConfig.name)' 2>/dev/null || true)"
  fi

  if [ -z "$ms" ]; then
    ms="$(gcloud endpoints services list --project "$PROJECT_ID" \
      --format='value(NAME)' | grep -E "^${API_ID}-.*\\.apigateway\\.${PROJECT_ID}\\.cloud\\.goog$" | head -n1)"
  fi

  [ -n "$ms" ] || die "Managed Service not found. Ensure gateway/config exists for API_ID=$API_ID"
  echo "$ms"
}


