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
  local env_file="$root/.env"
  if [ ! -f "$env_file" ]; then
    die "No .env found at repo root ($root). Run: make env-example and edit .env"
  fi
  # shellcheck disable=SC1090
  set -a
  . "$env_file"
  set +a
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


