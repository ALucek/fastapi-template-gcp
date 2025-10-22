#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env
ensure_command gcloud

ok() { echo -e "${GREEN}✔${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err() { echo -e "${RED}✖${NC} $*"; }

PASS=1

# 1) gcloud and project
if gcloud config get-value account >/dev/null 2>&1; then
  ACCNT="$(gcloud config get-value account 2>/dev/null)"
  ok "gcloud logged in as $ACCNT"
else
  err "gcloud not logged in"; PASS=0
fi

require_env_vars PROJECT_ID REGION SERVICE API_ID GATEWAY_ID || PASS=0

# 2) required APIs
REQ_APIS=(run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com apigateway.googleapis.com servicemanagement.googleapis.com servicecontrol.googleapis.com secretmanager.googleapis.com apikeys.googleapis.com)
ENABLED="$(gcloud services list --enabled --project "$PROJECT_ID" --format='value(config.name)')"
MISSING=()
for A in "${REQ_APIS[@]}"; do
  if ! grep -q "^${A}$" <<< "$ENABLED"; then MISSING+=("$A"); fi
done
if [ ${#MISSING[@]} -eq 0 ]; then
  ok "Required APIs enabled"
else
  err "Missing enabled APIs: ${MISSING[*]}"; PASS=0
fi

# 3) Cloud Run
if URL="$(cloud_run_url)"; then
  ok "Cloud Run URL: $URL"
else
  err "Cloud Run service not found: $SERVICE"; PASS=0
fi

# 4) Gateway
HOST="$(gcloud api-gateway gateways describe "$GATEWAY_ID" --location "$REGION" --project "$PROJECT_ID" --format='value(defaultHostname)' 2>/dev/null || true)"
if [ -n "$HOST" ]; then
  ok "Gateway Hostname: https://${HOST}"
else
  err "Gateway not found or no hostname. Run gw-update or init."; PASS=0
fi

# 5) IAM binding
if [ -z "${GATEWAY_SA:-}" ]; then
  GATEWAY_SA="apigw-invoker@${PROJECT_ID}.iam.gserviceaccount.com"
fi
POLICY="$(gcloud run services get-iam-policy "$SERVICE" --region "$REGION" --project "$PROJECT_ID" --format=json 2>/dev/null || echo '{}')"
if echo "$POLICY" | jq -e '.bindings[]? | select(.role=="roles/run.invoker") | .members[]? | select(.=="serviceAccount:'"$GATEWAY_SA"'")' >/dev/null; then
  ok "IAM: Gateway SA has run.invoker"
else
  err "IAM: Missing run.invoker for $GATEWAY_SA on $SERVICE"; PASS=0
fi

# 6) Probes
if command -v curl >/dev/null 2>&1; then
  if [ -n "$URL" ]; then
    CODE_CR=$(curl -s -o /dev/null -w "%{http_code}" "$URL/v1/healthz" || true)
    if [ "$CODE_CR" = "403" ] || [ "$CODE_CR" = "401" ]; then
      ok "Direct Cloud Run probe expected denial ($CODE_CR)"
    else
      warn "Direct Cloud Run probe returned $CODE_CR (expected 403/401)"
    fi
  fi
  if [ -n "$HOST" ]; then
    CODE_GW=$(curl -s -o /dev/null -w "%{http_code}" "https://${HOST}/v1/healthz" || true)
    if [ "$CODE_GW" = "200" ]; then
      ok "Gateway healthz 200"
    else
      warn "Gateway healthz returned $CODE_GW"
    fi
  fi
else
  warn "curl not installed; skipping probes"
fi

if [ "$PASS" = "1" ]; then
  ok "Doctor: PASS"
  exit 0
else
  err "Doctor: FAIL"
  exit 1
fi


