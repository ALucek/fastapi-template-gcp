#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

load_env
ensure_command gcloud
require_env_vars PROJECT_ID REGION REPO IMAGE TAG SERVICE

# Ensure Artifact Registry repo exists (idempotent safe)
gcloud artifacts repositories create "$REPO" \
  --repository-format=docker \
  --location="$REGION" \
  --project "$PROJECT_ID" >/dev/null 2>&1 || true

IMG_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}"

echo "Building and pushing image: $IMG_URI"
gcloud builds submit \
  --tag "$IMG_URI" \
  --project "$PROJECT_ID"

echo "Deploying Cloud Run service: $SERVICE"
gcloud run deploy "$SERVICE" \
  --image "$IMG_URI" \
  --region "$REGION" \
  --no-allow-unauthenticated \
  --min-instances=0 \
  --max-instances=10 \
  --concurrency=80 \
  --cpu=1 \
  --memory=512Mi \
  --cpu-throttling \
  --project "$PROJECT_ID"

URL="$(cloud_run_url)"
echo "Cloud Run URL: $URL"


