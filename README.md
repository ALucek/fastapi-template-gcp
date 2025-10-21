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

API_ID="fastapi-api"              
GATEWAY_ID="fastapi-gw"           
GATEWAY_SA="apigw-invoker@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud api-gateway apis create "$API_ID" --project "$PROJECT_ID"

gcloud iam service-accounts create apigw-invoker \
  --display-name="API Gateway Invoker" \
  --project "$PROJECT_ID" || true

gcloud run services add-iam-policy-binding "$SERVICE" \
  --region "$REGION" \
  --member="serviceAccount:${GATEWAY_SA}" \
  --role="roles/run.invoker" \
  --project "$PROJECT_ID"



gcloud api-gateway api-configs create "$CONFIG_ID" \
  --api="$API_ID" \
  --openapi-spec="deploy/gateway-openapi.yaml" \
  --project="$PROJECT_ID" \
  --backend-auth-service-account="$GATEWAY_SA"

CONFIG_ID="fastapi-config-$(date +%Y%m%d-%H%M%S)"

GATEWAY_ID="fastapi-gw"


RUN_URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')"
RENDERED="/tmp/openapi.rendered.yaml"
sed "s#https://YOUR_CLOUD_RUN_URL#${RUN_URL}#g" deploy/gateway-openapi.yaml > "$RENDERED"

CONFIG_ID="fastapi-config-$(date +%Y%m%d-%H%M%S)"
gcloud api-gateway api-configs create "$CONFIG_ID" \
  --api="$API_ID" \
  --openapi-spec="$RENDERED" \
  --project="$PROJECT_ID" \
  --backend-auth-service-account="apigw-invoker@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud api-gateway gateways update "$GATEWAY_ID" \
  --api="$API_ID" --api-config="$CONFIG_ID" \
  --location="$REGION" --project="$PROJECT_ID"
