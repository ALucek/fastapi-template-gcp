#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env
ensure_command gcloud
require_env_vars PROJECT_ID REGION REPO IMAGE TAG SERVICE API_ID GATEWAY_ID

if [ -z "${GATEWAY_SA:-}" ]; then
  GATEWAY_SA="apigw-invoker@${PROJECT_ID}.iam.gserviceaccount.com"
fi

echo "Enabling required Google APIs (idempotent)"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  apigateway.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  secretmanager.googleapis.com \
  apikeys.googleapis.com \
  --project "$PROJECT_ID"

echo "Ensuring Artifact Registry repo exists (idempotent)"
gcloud artifacts repositories create "$REPO" \
  --repository-format=docker \
  --location="$REGION" \
  --project "$PROJECT_ID" >/dev/null 2>&1 || true

SA_NAME="${GATEWAY_SA%@*}"
if [[ "$GATEWAY_SA" != *"@"* ]]; then
  die "GATEWAY_SA must be a full service account email, got: $GATEWAY_SA"
fi

echo "Ensuring gateway service account exists: $GATEWAY_SA"
gcloud iam service-accounts create "$SA_NAME" \
  --display-name="API Gateway Invoker" \
  --project "$PROJECT_ID" >/dev/null 2>&1 || true

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
RUN_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo "Granting project-level Secret Manager access to ${RUN_SA}"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${RUN_SA}" \
  --role="roles/secretmanager.secretAccessor" >/dev/null 2>&1 || true

echo "Building and deploying Cloud Run service"
bash "$SCRIPT_DIR/build_and_deploy.sh"

echo "Granting Cloud Run invoker role to $GATEWAY_SA on service $SERVICE"
gcloud run services add-iam-policy-binding "$SERVICE" \
  --region "$REGION" --project "$PROJECT_ID" \
  --member="serviceAccount:${GATEWAY_SA}" \
  --role="roles/run.invoker" >/dev/null 2>&1 || true

echo "Rendering OpenAPI and updating API Gateway"
bash "$SCRIPT_DIR/update_gateway.sh"

URL="$(cloud_run_url)"
HOST="$(gcloud api-gateway gateways describe "$GATEWAY_ID" \
  --location "$REGION" --project "$PROJECT_ID" \
  --format='value(defaultHostname)' 2>/dev/null || true)"

echo "Cloud Run URL: $URL"
if [ -n "$HOST" ]; then
  echo "Gateway Hostname: https://${HOST}"
fi


