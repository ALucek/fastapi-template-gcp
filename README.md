## FastAPI on Cloud Run behind API Gateway

Minimal template to run FastAPI on Cloud Run as a private service, fronted by API Gateway enforcing Google API Key auth (`x-api-key`).

### Security model (high level)

- Cloud Run service is private (no `allUsers` invoke)
- API Gateway uses an invoker service account to call Cloud Run
- Selected routes enforce Google API key via Gateway security definition

### Prerequisites

- gcloud CLI installed and logged in
- jq installed (for key scripts)
- Dockerfile binds `0.0.0.0:$PORT` (see `docker/gunicorn_conf.py`)
- Env files scaffolded (split by concern)

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
make env-examples
# edit .env.infra and .env.app
# optional: edit .env.deploy.dev / .env.deploy.prod
```

### Quickstart (automation)

```bash
# one-time or idempotent project init (enable APIs, SA, deploy, gateway)
make init

# build & deploy Cloud Run (private)
make build-deploy            # uses .env.infra + .env.deploy.dev by default; override with DEPLOY_ENV=prod

# update API Gateway spec and point gateway to new config
make gw-update

# create a Google API key restricted to the managed service (does not print key string)
make api-key

# key management
make keys
make rotate-key OLD=<KEY_NAME> [DELETE=true] [PRINT=true]
make del-key KEY_NAME=<KEY_NAME> [YES=true]

# local dev (reload)
make dev                     # uses .env.infra + .env.app by default

# diagnostics
make doctor
```

Advanced:

```bash
# If you need the key string just once (avoid printing normally):
bash scripts/create_api_key.sh --print-key
```

### Manual deployment and deep-dive docs

- Manual deployment (all gcloud steps): see [MANUAL_DEPLOYMENT.md](MANUAL_DEPLOYMENT.md).
- Scripts and Make targets reference: see [scripts/SCRIPTS.md](scripts/SCRIPTS.md).
- OpenAPI v2 spec (source of truth for API Gateway): `deploy/gateway-openapi.yaml`.

### Configuration & secrets (short)

- Non-secret app config for local/dev → `.env.app` (e.g., `ENV`, `LOG_LEVEL`, `PORT`).
- Infra/deploy identifiers → `.env.infra` (e.g., `PROJECT_ID`, `REGION`, `SERVICE`).
- Deployment-time bindings → `.env.deploy.<env>` with:
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