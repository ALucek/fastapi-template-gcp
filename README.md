## FastAPI on Cloud Run behind API Gateway

Minimal template to manually run FastAPI on Cloud Run as a private service, fronted by API Gateway enforcing Google API Key auth (`x-api-key`).

### How it works (flow)

- Request hits API Gateway at `https://<gateway-host>`.
- For protected routes, Gateway validates the Google API key from the `x-api-key` header (open routes skip this).
- Gateway calls Cloud Run using its invoker service account (`roles/run.invoker`).
- Cloud Run remains private; direct calls to the Cloud Run URL return 403/401, while calls through Gateway succeed.

### Security model

- Cloud Run service is private (no `allUsers` invoke)
- API Gateway uses an invoker service account to call Cloud Run
- Selected routes enforce Google API key via Gateway security definition

### Prerequisites

- gcloud CLI installed and logged in
- jq installed (for key scripts)

### End-to-end in 5 steps

1) Authenticate, select project, scaffold env files

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
make env-examples
# edit .env.infra, .env.app, .env.deploy
```

2) Initialize everything (enable APIs, build & deploy Cloud Run, create/update Gateway)

```bash
make init
```

3) Create an API key (print it once for testing)

```bash
make api-key
```

4) Test through the Gateway

```bash
HOST="$(gcloud api-gateway gateways describe "$GATEWAY_ID" \
  --location "$REGION" --project "$PROJECT_ID" --format='value(defaultHostname)')"

curl -i "https://${HOST}/v1/healthz"                 # open route → 200
curl -i -H "x-api-key: ${KEY}" "https://${HOST}/v1/hello"  # protected → 200
```

5) Verify setup

```bash
make doctor
```

### Manual deployment and deep-dive docs

- Manual deployment (all gcloud steps): see [MANUAL_DEPLOYMENT.md](MANUAL_DEPLOYMENT.md).
- Scripts and Make targets reference: see [scripts/SCRIPTS.md](scripts/SCRIPTS.md).
- OpenAPI v2 spec (source of truth for API Gateway): `deploy/gateway-openapi.yaml`.

### Scripts at a glance

- `scripts/init_project.sh`: Enable required APIs, ensure Artifact Registry and Gateway SA, build & deploy Cloud Run, grant `run.invoker`, render OpenAPI, create/update Gateway.
- `scripts/build_and_deploy.sh`: Build container with Cloud Build and deploy Cloud Run as private (optional `SECRETS`, `ENV_VARS`).
- `scripts/update_gateway.sh`: Inject Cloud Run URL into OpenAPI, create API config, and create/update Gateway.
- `scripts/create_api_key.sh`: Create a Google API key and restrict it to the Gateway managed service. Config via env: `PRINT_KEY=1`, `KEY_PREFIX=<str>`.
- `scripts/list_api_keys.sh`: List API keys with restrictions.
- `scripts/delete_api_key.sh`: Delete an API key (set `YES=true` to skip confirmation).
- `scripts/dev_uvicorn.sh`: Run local dev server with reload.
- `scripts/doctor.sh`: Validate environment, required APIs, IAM, and probe health endpoints.

### Make targets

These convenience targets wrap the scripts in `scripts/` and set sane defaults.

- **`env-examples`**: Create missing `.env.infra`, `.env.app`, `.env.deploy` from their `*.example` templates.

```bash
make env-examples
```

- **`init`**: End-to-end project bootstrap (enable APIs, build & deploy Cloud Run, grant IAM, render OpenAPI, create/update Gateway).

```bash
make init
```

- **`build-deploy`**: Build the container with Cloud Build and deploy to Cloud Run.

```bash
make build-deploy
```

- **`gw-update`**: Regenerate API config from `deploy/gateway-openapi.yaml` and update/create the API Gateway.

```bash
make gw-update
```

- **`api-key`**: Create a Google API key restricted to this Gateway. Optionally prefix the key name.

```bash
# basic
make api-key

# prefix key name
make api-key PREFIX=myapp

# print key once
make api-key PRINT_KEY=1
```

- **`keys`**: List API keys and their restrictions.

```bash
make keys
```

- **`del-key`**: Delete an API key by name. Requires `KEY_NAME`. Add `YES=true` to skip confirmation.

```bash
make del-key KEY_NAME=<KEY_NAME>
make del-key KEY_NAME=<KEY_NAME> YES=true
```

- **`dev`**: Run local FastAPI server with autoreload.

```bash
make dev
```

- **`doctor`**: Run environment and deployment diagnostics.

```bash
make doctor
```

### Configuration & secrets

- Non-secret app config for local/dev → `.env.app` (e.g., `ENV`, `LOG_LEVEL`, `PORT`).
- Infra/deploy identifiers → `.env.infra` (e.g., `PROJECT_ID`, `REGION`, `SERVICE`).
- Deployment-time bindings → `.env.deploy` with:
  - `SECRETS` (Secret Manager names, not values), e.g., `API_TOKEN=api-token:latest`
  - `ENV_VARS` (regular env vars), e.g., `ENV=prod,LOG_LEVEL=info`

### Local development

```bash
make dev
# app served at http://localhost:${PORT:-8080}
```

### Day-2 basics

- App change → `make build-deploy`
- Gateway spec change → `make gw-update`