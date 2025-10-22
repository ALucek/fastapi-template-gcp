# FastAPI on Cloud Run behind API Gateway — One-Pass Deployment README

## 0) Prereqs

* gcloud CLI installed and logged in
* A working Dockerfile (gunicorn/uvicorn binding to `0.0.0.0:$PORT`)
* A Swagger **v2 (OpenAPI 2.0)** file at `deploy/gateway-openapi.yaml` (template below)

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

---

## 1) Vars (edit once)

```bash
export PROJECT_ID="fastapi-repo-2"
export REGION="us-central1"

export REPO="fastapi-repo"
export IMAGE="fastapi-cloudrun"
export TAG="v1"

export SERVICE="fastapi-api"

export API_ID="fastapi-api"
export GATEWAY_ID="fastapi-gw"
export GATEWAY_SA="apigw-invoker@${PROJECT_ID}.iam.gserviceaccount.com"
```

---

## 2) Enable services (safe to re-run)

```bash
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  apigateway.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  apikeys.googleapis.com \
  --project "$PROJECT_ID"
```

---

## 3) Build & push image (Artifact Registry)

```bash
gcloud artifacts repositories create "$REPO" \
  --repository-format=docker \
  --location="$REGION" \
  --project "$PROJECT_ID" || true

gcloud builds submit \
  --tag "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}" \
  --project "$PROJECT_ID"
```

---

## 4) Deploy Cloud Run **private** (no public invoke)

> App-level auth is **removed**; API Gateway will handle auth.

```bash
gcloud run deploy "$SERVICE" \
  --image "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}" \
  --region "$REGION" \
  --no-allow-unauthenticated \
  --min-instances=0 \
  --max-instances=10 \
  --concurrency=80 \
  --cpu=1 \
  --memory=512Mi \
  --cpu-throttling \
  --project "$PROJECT_ID"
```

Grab the Cloud Run URL (backend target for gateway):

```bash
export URL="$(gcloud run services describe "$SERVICE" \
  --region "$REGION" --project "$PROJECT_ID" \
  --format='value(status.url)')"
echo "Cloud Run URL: $URL"
```

---

## 5) Create the API Gateway caller service account & grant invoke

```bash
gcloud iam service-accounts create apigw-invoker \
  --display-name="API Gateway Invoker" \
  --project "$PROJECT_ID" || true

gcloud run services add-iam-policy-binding "$SERVICE" \
  --region "$REGION" --project "$PROJECT_ID" \
  --member="serviceAccount:${GATEWAY_SA}" \
  --role="roles/run.invoker"
```

---

## 6) Gateway spec (Swagger v2) → render → create config

**`deploy/gateway-openapi.yaml` (template)**

```yaml
swagger: "2.0"
info:
  title: fastapi-cloudrun
  version: "1.0.0"

schemes: [https]
basePath: /

paths:
  /v1/hello:
    get:
      operationId: getHello
      # Gateway enforces Google API key here
      security:
        - api_key: []
      x-google-backend:
        address: https://YOUR_CLOUD_RUN_URL         # replaced at render time
        path_translation: APPEND_PATH_TO_ADDRESS
      responses:
        "200": { description: OK }

  /v1/healthz:
    get:
      operationId: getHealthz
      x-google-backend:
        address: https://YOUR_CLOUD_RUN_URL
        path_translation: APPEND_PATH_TO_ADDRESS
      responses:
        "200": { description: OK }

securityDefinitions:
  api_key:
    type: apiKey
    in: header
    name: x-api-key
```

**Render with your actual Cloud Run URL & create config**

```bash
RENDERED="/tmp/openapi.rendered.yaml"
sed "s#https://YOUR_CLOUD_RUN_URL#${URL}#g" deploy/gateway-openapi.yaml > "$RENDERED"

gcloud api-gateway apis create "$API_ID" --project "$PROJECT_ID" || true

CONFIG_ID="fastapi-config-$(date +%Y%m%d-%H%M%S)"
gcloud api-gateway api-configs create "$CONFIG_ID" \
  --api="$API_ID" \
  --openapi-spec="$RENDERED" \
  --backend-auth-service-account="$GATEWAY_SA" \
  --project="$PROJECT_ID"
```

---

## 7) Create/Update the Gateway & get hostname

```bash
gcloud api-gateway gateways create "$GATEWAY_ID" \
  --api="$API_ID" --api-config="$CONFIG_ID" \
  --location="$REGION" --project "$PROJECT_ID" || true

gcloud api-gateway gateways update "$GATEWAY_ID" \
  --api="$API_ID" --api-config="$CONFIG_ID" \
  --location="$REGION" --project "$PROJECT_ID"

export GATEWAY_HOST="$(gcloud api-gateway gateways describe "$GATEWAY_ID" \
  --location "$REGION" --project "$PROJECT_ID" \
  --format='value(defaultHostname)')"
echo "Gateway Hostname: https://${GATEWAY_HOST}"
```

---

## 8) Create a **Google API key** (for Gateway) & test

**Create key and capture the *string***

```bash
CREATE_OUT="$(gcloud services api-keys create \
  --display-name="gw-dev-$(date +%Y%m%d-%H%M%S)" \
  --project "$PROJECT_ID" --format=json 2>/dev/null)"
KEY_NAME="$(jq -r '.response.name' <<<"$CREATE_OUT")"
KEY="$(jq -r '.response.keyString' <<<"$CREATE_OUT")"
echo "KEY_NAME=${KEY_NAME}"
echo "KEY=${KEY}"
```

**Discover the API Gateway Managed Service (MS)**

```bash
CONFIG_ID="$(gcloud api-gateway gateways describe "$GATEWAY_ID" \
  --location "$REGION" --project "$PROJECT_ID" --format='value(apiConfig)')"

if [ -z "$MS" ]; then
  MS="$(gcloud endpoints services list --project "$PROJECT_ID" \
        --format='value(NAME)' \
      | grep -E "^${API_ID}-.*\.apigateway\.${PROJECT_ID}\.cloud\.goog$" \
      | head -n1)"
fi

echo "Managed service: ${MS}"
```

**Enable MS in this project (idempotent)**

```bash
gcloud services enable "$MS" --project "$PROJECT_ID"

# --- Restrict the key to ONLY this MS ---
gcloud services api-keys update "$KEY_NAME" \
  --api-target="service=${MS}" \
  --project "$PROJECT_ID"
```

**Test the key**

```bash
# open route (no key)
curl -i "https://${GATEWAY_HOST}/v1/healthz"

# protected route (Gateway API key required)
curl -i -H "x-api-key: ${KEY}" "https://${GATEWAY_HOST}/v1/hello"

# protected route, no Auth test
curl -i -H "x-api-key: fake-key" "https://${GATEWAY_HOST}/v1/hello"
```

---

## 9) Keep Cloud Run **gateway-only**

If you ever had it public, remove `allUsers`:

```bash
gcloud run services remove-iam-policy-binding "$SERVICE" \
  --region "$REGION" --project "$PROJECT_ID" \
  --member="allUsers" --role="roles/run.invoker" || true
```

Verify:

```bash
# direct base URL should be 403 (private service)
curl -i "${URL}/v1/healthz"

# through gateway should be 200
curl -i "https://${GATEWAY_HOST}/v1/healthz"
curl -i -H "x-api-key: ${KEY}" "https://${GATEWAY_HOST}/v1/hello"
```

---

## Day-2: Updates

* **App code change** → Rebuild & deploy Cloud Run (still private):

  ```bash
  gcloud builds submit --tag "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}"
  gcloud run deploy "$SERVICE" \
    --image "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}" \
    --region "$REGION" --no-allow-unauthenticated
  ```

* **Gateway routing/auth change** → New config + point gateway to it:

  ```bash
  sed "s#https://YOUR_CLOUD_RUN_URL#${URL}#g" deploy/gateway-openapi.yaml > /tmp/openapi.rendered.yaml
  CONFIG_ID="fastapi-config-$(date +%Y%m%d-%H%M%S)"
  gcloud api-gateway api-configs create "$CONFIG_ID" \
    --api "$API_ID" --openapi-spec /tmp/openapi.rendered.yaml \
    --backend-auth-service-account "$GATEWAY_SA" --project "$PROJECT_ID"
  gcloud api-gateway gateways update "$GATEWAY_ID" \
    --api "$API_ID" --api-config "$CONFIG_ID" \
    --location "$REGION" --project "$PROJECT_ID"
  ```

---

## Troubleshooting (quick)

* **Gateway 401 “unregistered callers”** → you didn’t pass a **Google API key** that matches your `security` scheme (header `x-api-key`, or query `key` if you chose that).
* **Gateway 404 but direct URL 200** → add `path_translation: APPEND_PATH_TO_ADDRESS` to each operation.
* **Gateway 403 w/ Service Control** → ensure `servicemanagement` & `servicecontrol` APIs are enabled; if key is restricted, enable the **managed service** in this project.
* **Direct Cloud Run 403** → expected (service is private). Use Gateway.
* **Container readiness** → app must bind `0.0.0.0:$PORT`. For gunicorn:

  ```python
  bind = f"0.0.0.0:{os.getenv('PORT','8080')}"
  worker_class = "uvicorn.workers.UvicornWorker"
  ```