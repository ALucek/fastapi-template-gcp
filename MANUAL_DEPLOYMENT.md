## Manual deployment guide

This guide captures the full, copy-ready gcloud flow to deploy a private FastAPI service on Cloud Run fronted by API Gateway with Google API Key auth.

Prefer automation? See the Quickstart and Make targets in [README.md](README.md). The commands below are safe to re-run (idempotent where noted).

### Prerequisites

- gcloud CLI installed and authenticated
- jq installed
- Project variables exported in your shell or defined in `.env.infra` (see `.env.infra.example`)
- OpenAPI v2 spec at `deploy/gateway-openapi.yaml` (source of truth)

### Export required environment variables

```bash
# Core identifiers
export PROJECT_ID="your-gcp-project"
export REGION="us-central1"
export REPO="fastapi"
export IMAGE="fastapi"
export TAG="dev"
export SERVICE="fastapi"
export API_ID="fastapi"
export GATEWAY_ID="fastapi-gw"

# Gateway invoker Service Account (default used by scripts)
export GATEWAY_SA="apigw-invoker@${PROJECT_ID}.iam.gserviceaccount.com"

# OpenAPI spec path (override if you keep it elsewhere)
export OPENAPI_SPEC="deploy/gateway-openapi.yaml"

# Optional deploy-time settings
# Secret Manager bindings, e.g., API_TOKEN=api-token:latest
export SECRETS=""
# Regular env vars, e.g., ENV=prod,LOG_LEVEL=info
export ENV_VARS=""
```

### 1) Enable services

```bash
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
```

### 2) Build and push image (Artifact Registry)

```bash
gcloud artifacts repositories create "$REPO" \
  --repository-format=docker \
  --location="$REGION" \
  --project "$PROJECT_ID" || true

gcloud builds submit \
  --tag "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}" \
  --project "$PROJECT_ID"
```

### 3) Deploy Cloud Run (private)

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

Optional: attach secrets and/or regular env vars on deploy (requires Secret Manager access; see snippet below):

```bash
gcloud run deploy "$SERVICE" \
  --image "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}" \
  --region "$REGION" \
  --no-allow-unauthenticated \
  --set-secrets "${SECRETS}" \
  --set-env-vars "${ENV_VARS}" \
  --project "$PROJECT_ID"
```

Tuning: adjust scaling and concurrency later via update (mirrors the deploy flags above):

```bash
gcloud run services update "$SERVICE" \
  --region "$REGION" \
  --max-instances=10 \
  --concurrency=80 \
  --memory=512Mi
```

Get the Cloud Run URL (used when rendering the gateway spec):

```bash
export URL="$(gcloud run services describe "$SERVICE" \
  --region "$REGION" --project "$PROJECT_ID" \
  --format='value(status.url)')"
echo "Cloud Run URL: $URL"
```

If you plan to use `--set-secrets`, grant the Cloud Run runtime service account project-level Secret Manager access (idempotent):

```bash
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
RUN_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${RUN_SA}" \
  --role="roles/secretmanager.secretAccessor"
```

### 4) Gateway invoker service account and IAM binding

```bash
gcloud iam service-accounts create apigw-invoker \
  --display-name="API Gateway Invoker" \
  --project "$PROJECT_ID" || true

GATEWAY_SA="apigw-invoker@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud run services add-iam-policy-binding "$SERVICE" \
  --region "$REGION" --project "$PROJECT_ID" \
  --member="serviceAccount:${GATEWAY_SA}" \
  --role="roles/run.invoker"
```

### 5) Gateway spec (Swagger v2)

- Use the canonical spec at `deploy/gateway-openapi.yaml`.
- Security is enforced via a Google API key (`x-api-key` header) on protected routes.
- Optional quotas can be configured via Service Control extensions.

Optional quota example (snippet):

```yaml
# Root-level
x-google-management:
  metrics:
    - name: "hello-requests"
      displayName: "Hello requests"
      valueType: INT64
      metricKind: DELTA
  quota:
    limits:
      - name: "hello-per-minute"
        metric: "hello-requests"
        unit: "1/min/{project}"
        values: { STANDARD: 60 }

# On /v1/hello method
x-google-quota:
  metricCosts:
    hello-requests: 1
```

### 6) Render spec with Cloud Run URL and create API config

```bash
RENDERED="$(mktemp /tmp/openapi.rendered.XXXXXX.yaml)"
sed "s#https://YOUR_CLOUD_RUN_URL#${URL}#g" "${OPENAPI_SPEC:-deploy/gateway-openapi.yaml}" > "$RENDERED"

gcloud api-gateway apis create "$API_ID" --project "$PROJECT_ID" || true

CONFIG_ID="fastapi-config-$(date +%Y%m%d-%H%M%S)"

gcloud api-gateway api-configs create "$CONFIG_ID" \
  --api="$API_ID" \
  --openapi-spec="$RENDERED" \
  --backend-auth-service-account="$GATEWAY_SA" \
  --project="$PROJECT_ID"
```

### 7) Create/update the Gateway and get hostname

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

### 8) Create a Google API key and restrict it to the managed service

```bash
CREATE_OUT="$(gcloud services api-keys create \
  --display-name="gw-dev-$(date +%Y%m%d-%H%M%S)" \
  --project "$PROJECT_ID" --format=json 2>/dev/null)"
KEY_NAME="$(jq -r '.response.name' <<<"$CREATE_OUT")"
KEY="$(jq -r '.response.keyString' <<<"$CREATE_OUT")"
echo "KEY_NAME=${KEY_NAME}"
echo "KEY=${KEY}"
```

Discover the API Gateway Managed Service (MS):

```bash
CONFIG_ID="$(gcloud api-gateway gateways describe "$GATEWAY_ID" \
  --location "$REGION" --project "$PROJECT_ID" --format='value(apiConfig)')"

MS="$(gcloud api-gateway api-configs describe "$CONFIG_ID" \
  --api="$API_ID" --project="$PROJECT_ID" \
  --format='value(googleServiceConfig.name)')"

if [ -z "$MS" ]; then
  MS="$(gcloud endpoints services list --project "$PROJECT_ID" \
        --format='value(NAME)' \
      | grep -E "^${API_ID}-.*\.apigateway\.${PROJECT_ID}\.cloud\.goog$" \
      | head -n1)"
fi

echo "Managed service: ${MS}"
```

Enable MS in this project and restrict the key:

```bash
gcloud services enable "$MS" --project "$PROJECT_ID"

gcloud services api-keys update "$KEY_NAME" \
  --api-target="service=${MS}" \
  --project "$PROJECT_ID"
```

#### List API keys with restrictions

```bash
# Tab-separated: DISPLAY_NAME \t NAME \t CREATE_TIME \t RESTRICTED_SERVICES
gcloud services api-keys list \
  --project "$PROJECT_ID" --format=json \
| jq -r '.[]? | [.displayName, .name, .createTime, ([.restrictions.apiTargets[]?.service?] | map(select(. != null)) | join(","))] | @tsv'
```

#### Delete an API key (by resource name or display name)

```bash
# If you have the resource name (projects/.../keys/...):
gcloud services api-keys delete "$KEY_NAME" --project "$PROJECT_ID" --quiet

# If you only know the display name, resolve the most recent match to NAME:
KEY_NAME="$(gcloud services api-keys list --project "$PROJECT_ID" --format=json \
  | jq -r --arg dn "DISPLAY_NAME_HERE" '[.[] | select(.displayName == $dn)] | sort_by(.createTime) | last | .name // empty')"
[ -n "$KEY_NAME" ] && gcloud services api-keys delete "$KEY_NAME" --project "$PROJECT_ID" --quiet
```

### 9) Test through the gateway (and ensure Cloud Run stays private)

```bash
# open route (no key)
curl -i "https://${GATEWAY_HOST}/v1/healthz"

# protected route (Gateway API key required)
curl -i -H "x-api-key: ${KEY}" "https://${GATEWAY_HOST}/v1/hello"

# protected route, invalid key
curl -i -H "x-api-key: fake-key" "https://${GATEWAY_HOST}/v1/hello"
```

Keep Cloud Run gateway-only (remove public access if it was ever added):

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

### 10) Verification checklist (doctor parity)

```bash
# Logged in?
gcloud config get-value account

# Required APIs enabled?
REQ_APIS=(run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com apigateway.googleapis.com servicemanagement.googleapis.com servicecontrol.googleapis.com secretmanager.googleapis.com apikeys.googleapis.com)
ENABLED="$(gcloud services list --enabled --project "$PROJECT_ID" --format='value(config.name)')"
for A in "${REQ_APIS[@]}"; do grep -q "^${A}$" <<< "$ENABLED" || echo "Missing: $A"; done

# Cloud Run URL exists, direct probe is denied (403/401)
URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT_ID" --format='value(status.url)')"
[ -n "$URL" ] && curl -i "$URL/v1/healthz"

# Gateway hostname and probe
GATEWAY_HOST="$(gcloud api-gateway gateways describe "$GATEWAY_ID" --location "$REGION" --project "$PROJECT_ID" --format='value(defaultHostname)')"
[ -n "$GATEWAY_HOST" ] && curl -i "https://${GATEWAY_HOST}/v1/healthz"

# IAM: Gateway SA has roles/run.invoker on the service
GATEWAY_SA="${GATEWAY_SA:-apigw-invoker@${PROJECT_ID}.iam.gserviceaccount.com}"
gcloud run services get-iam-policy "$SERVICE" --region "$REGION" --project "$PROJECT_ID" --format=json \
| jq -e '.bindings[]? | select(.role=="roles/run.invoker") | .members[]? | select(.=="serviceAccount:'"$GATEWAY_SA"'")' >/dev/null \
  && echo "OK: Gateway SA has run.invoker" || echo "Missing run.invoker for $GATEWAY_SA"
```

### 11) Logs and monitoring

```bash
# Tail last 100 logs from Cloud Run
gcloud run services logs read "$SERVICE" --region "$REGION" --limit 100

# Gateway-side logs (Service Control) → Logs Explorer filter:
# resource.type="api" AND resource.labels.service="<your-managed-service>"
```

To filter by request ID from `x-cloud-trace-context`:

```bash
gcloud logging read \
  "resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE AND textPayload:$(echo \"$TRACE_ID\")" \
  --limit 50 --format="value(textPayload)"
```

### 12) Optional hardening checklist

```bash
# IAM audit – ensure only gateway SA can invoke
gcloud run services get-iam-policy "$SERVICE" --region "$REGION" \
  --format='json(bindings[?role=="roles/run.invoker"])'

# Autoscaling caps (dev vs prod)
gcloud run services update "$SERVICE" --region "$REGION" --max-instances=2   # dev
gcloud run services update "$SERVICE" --region "$REGION" --max-instances=50  # prod

# Env vars
gcloud run services update "$SERVICE" --region "$REGION" \
  --set-env-vars="ENV=prod,LOG_LEVEL=info"

# CORS – add FastAPI CORSMiddleware if browser callers (skip for server-to-server)
```

### 13) Cleanup

```bash
# Delete a gateway config (doesn't affect live gateway unless attached)
gcloud api-gateway api-configs delete "$CONFIG_ID" --api "$API_ID" --project "$PROJECT_ID"

# Delete a gateway
gcloud api-gateway gateways delete "$GATEWAY_ID" \
  --location "$REGION" --project "$PROJECT_ID"

# Delete an API key
gcloud services api-keys delete "$KEY_NAME" --project "$PROJECT_ID" --quiet

# Delete Cloud Run service (and image if you want)
gcloud run services delete "$SERVICE" --region "$REGION" --quiet
gcloud artifacts docker images delete \
  "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}" --quiet
```

### Day-2 updates

- App code change → Rebuild & deploy Cloud Run (still private)

```bash
gcloud builds submit --tag "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}"
gcloud run deploy "$SERVICE" \
  --image "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/${IMAGE}:${TAG}" \
  --region "$REGION" --no-allow-unauthenticated
# optionally:
#  --set-secrets "${SECRETS}" \
#  --set-env-vars "${ENV_VARS}"
```

- Gateway routing/auth change → New config + point gateway to it

```bash
RENDERED="$(mktemp /tmp/openapi.rendered.XXXXXX.yaml)"
sed "s#https://YOUR_CLOUD_RUN_URL#${URL}#g" "${OPENAPI_SPEC:-deploy/gateway-openapi.yaml}" > "$RENDERED"
CONFIG_ID="fastapi-config-$(date +%Y%m%d-%H%M%S)"
gcloud api-gateway api-configs create "$CONFIG_ID" \
  --api "$API_ID" --openapi-spec "$RENDERED" \
  --backend-auth-service-account "$GATEWAY_SA" --project "$PROJECT_ID"
gcloud api-gateway gateways update "$GATEWAY_ID" \
  --api "$API_ID" --api-config "$CONFIG_ID" \
  --location "$REGION" --project "$PROJECT_ID"
```

### Troubleshooting

- Gateway 401 “unregistered callers” → you didn’t pass a Google API key that matches your `security` scheme (`x-api-key` header, or query `key` if you chose that).
- Gateway 404 but direct URL 200 → add `path_translation: APPEND_PATH_TO_ADDRESS` to each operation.
- Gateway 403 w/ Service Control → ensure `servicemanagement` & `servicecontrol` APIs are enabled; if key is restricted, enable the managed service in this project.
- Direct Cloud Run 403 → expected (service is private). Use Gateway.
- Container readiness → app must bind `0.0.0.0:$PORT` (see `docker/gunicorn_conf.py`).


