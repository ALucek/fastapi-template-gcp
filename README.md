gcloud auth login         # authenticate with Google Cloud
gcloud config set project YOUR_PROJECT_ID

gcloud services enable run.googleapis.com
gcloud services enable artifactregistry.googleapis.com

gcloud artifacts repositories create fastapi-repo \
    --repository-format=docker \
    --location=us-central1

PROJECT_ID="fastapi-repo-testing"
REGION="us-central1"
REPO="fastapi-repo"
IMAGE="fastapi-cloudrun"
TAG="v1"

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}

SECRET_NAME="api-key-secret"

# create secret (automatic replication)
gcloud secrets create ${SECRET_NAME} --replication-policy="automatic"

# add version
echo -n "YOUR_VALUE" | gcloud secrets versions add "$SECRET_NAME" \
  --replication-policy="automatic" \
  --data-file=-

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

SVC="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --member="serviceAccount:${SVC}" \
  --role="roles/secretmanager.secretAccessor" \
  --project "$PROJECT_ID"

  SERVICE="fastapi-api"

gcloud run deploy ${SERVICE} \
  --image ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG} \
  --region ${REGION} \
  --allow-unauthenticated \
  --update-secrets=API_KEY=${SECRET_NAME}:1

  URL=$(gcloud run services describe ${SERVICE} --region ${REGION} \
  --format='value(status.url)')
curl -s -H "x-api-key: strong-random-key" "${URL}/v1/hello"

gcloud run services logs read "$SERVICE" --region "$REGION" --limit 200