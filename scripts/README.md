## Scripts and Make targets reference

This is the authoritative reference for the automation scripts and `make` targets. Scripts auto-load variables via `scripts/lib.sh`, which selects default env files by concern. For a manual, step-by-step deploy guide see [MANUAL_DEPLOYMENT.md](../MANUAL_DEPLOYMENT.md).

### Required tools

- gcloud
- jq (for key management scripts)

### Environment files and variables

Run `make env-examples` to scaffold split env files:
- `.env.infra` – infra identifiers: `PROJECT_ID`, `REGION`, `REPO`, `IMAGE`, `TAG`, `SERVICE`, `API_ID`, `GATEWAY_ID`, optional `GATEWAY_SA`, `OPENAPI_SPEC`.
- `.env.app` – local app config: `ENV`, `LOG_LEVEL`, `PORT`.
- `.env.deploy` – `SECRETS` and `ENV_VARS` for deploy-time bindings.

Scripts choose sensible defaults:
- Dev server uses `.env.infra:.env.app`.
- Build & deploy uses `.env.infra:.env.deploy`.
- Others use `.env.infra`.
Override by setting `ENV_FILES` (colon-separated) if needed.

### Make target → Script mapping

| Make target     | Script                         | Purpose                                      | Key flags                                    |
|-----------------|--------------------------------|----------------------------------------------|----------------------------------------------|
| `env-examples`  | —                              | Create split env files from `.example` files | —                                            |
| `build-deploy`  | `scripts/build_and_deploy.sh`  | Build image and deploy Cloud Run (private)   | `SECRETS`, `ENV_VARS` via `.env`              |
| `gw-update`     | `scripts/update_gateway.sh`    | Render OpenAPI with URL and update gateway   | —                                            |
| `init`          | `scripts/init_project.sh`      | One-time/init: enable APIs, SA, deploy, GW   | —                                            |
| `api-key`       | `scripts/create_api_key.sh`    | Create API key restricted to managed service | `KEY_PREFIX`, `PRINT_KEY=1`                  |
| `keys`          | `scripts/list_api_keys.sh`     | List API keys with restrictions              | —                                            |
| `del-key`       | `scripts/delete_api_key.sh`    | Delete API key (confirm unless YES=true)     | `YES=true`                                   |
| `dev`           | `scripts/dev_uvicorn.sh`       | Run uvicorn locally with reload              | Uses `PORT`                                  |
| `doctor`        | `scripts/doctor.sh`            | Validate setup and probe endpoints           | —                                            |

---

### scripts/lib.sh (shared helpers)

Provides: `die`, `ensure_command`, `require_env_vars`, `load_env` (layered: defaults per script, `ENV_FILES` override), `timestamp`, `cloud_run_url`, `managed_service_name`.

---

### scripts/init_project.sh

- Synopsis: Enable required APIs, ensure Artifact Registry and Gateway SA, build & deploy Cloud Run, grant `run.invoker`, update API Gateway.
- Requires env: `PROJECT_ID`, `REGION`, `REPO`, `IMAGE`, `TAG`, `SERVICE`, `API_ID`, `GATEWAY_ID` (optional `GATEWAY_SA`).
- Flags: None
- Idempotency: Safe to re-run; create calls use `|| true` where applicable.

### scripts/build_and_deploy.sh

- Synopsis: Build container image with Cloud Build and deploy to Cloud Run as private.
- Requires env: `PROJECT_ID`, `REGION`, `REPO`, `IMAGE`, `TAG`, `SERVICE`.
- Optional env:
  - `SECRETS`: comma-separated secret bindings (e.g., `API_TOKEN=api-token:latest`).
  - `ENV_VARS`: comma-separated env vars (e.g., `ENV=prod,LOG_LEVEL=info`).
  - `MAX_INSTANCES` (default `10`)
  - `CONCURRENCY` (default `80`)
  - `MEMORY` (default `512Mi`)
- Output: Prints Cloud Run URL after deploy.

### scripts/update_gateway.sh

- Synopsis: Render OpenAPI spec by injecting Cloud Run URL, create API config, create/update gateway.
- Requires env: `PROJECT_ID`, `REGION`, `API_ID`, `GATEWAY_ID`, `OPENAPI_SPEC`, `SERVICE` (to resolve URL). Optional `GATEWAY_SA`.
- Behavior: Creates unique config IDs with timestamp; gateway is created if missing and then updated to new config.

### scripts/create_api_key.sh

- Synopsis: Create a Google API key and restrict it to the API Gateway managed service.
- Requires env: `PROJECT_ID`, `API_ID`, `GATEWAY_ID`.
- Configuration via env:
  - `PRINT_KEY=1`: print the key string once (avoid storing/printing routinely).
  - `KEY_PREFIX` (or `PREFIX`): change display name prefix (default `gw`).
- Output: `KEY_NAME` and managed service; optionally `KEY`.



### scripts/list_api_keys.sh

- Synopsis: List API keys with display name, resource name, create time, and restricted services.
- Requires env: `PROJECT_ID`.

### scripts/delete_api_key.sh

- Synopsis: Delete an API key by resource name or display name.
- Requires env: `PROJECT_ID`.
- Usage: `scripts/delete_api_key.sh <KEY_NAME|displayName>`
- Behavior: Prompts for confirmation unless `YES=true` is set.

### scripts/dev_uvicorn.sh

- Synopsis: Run local development server with `uvicorn --reload`.
- Env: `PORT` (default `8080`).

### scripts/doctor.sh

- Synopsis: Perform environment and deployment checks (gcloud login, required APIs, Cloud Run URL, Gateway hostname, IAM binding) and HTTP probes to health endpoints.
- Requires: `gcloud`, `curl` (optional), `jq`.
- Exit codes: non-zero on failure.


