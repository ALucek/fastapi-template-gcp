.PHONY: env-example env-examples api-key build-deploy gw-update init keys del-key dev doctor

ROOT := $(shell pwd)

env-examples:
	@[ -f $(ROOT)/.env.infra ] || (cp $(ROOT)/.env.infra.example $(ROOT)/.env.infra && echo ".env.infra created") || true
	@[ -f $(ROOT)/.env.app ] || (cp $(ROOT)/.env.app.example $(ROOT)/.env.app && echo ".env.app created") || true
	@[ -f $(ROOT)/.env.deploy ] || (cp $(ROOT)/.env.deploy.example $(ROOT)/.env.deploy && echo ".env.deploy created") || true

api-key:
	CMD="bash scripts/create_api_key.sh"; \
	[ -n "$(PREFIX)" ] && CMD="$$CMD --prefix $(PREFIX)"; \
	$$CMD

build-deploy:
	bash scripts/build_and_deploy.sh

gw-update:
	bash scripts/update_gateway.sh

init:
	bash scripts/init_project.sh



keys:
	bash scripts/list_api_keys.sh

del-key:
	@if [ -z "$(KEY_NAME)" ]; then echo "Usage: make del-key KEY_NAME=<KEY_NAME> [YES=true]" && exit 1; fi; \
	YES_FLAG=""; \
	[ "$(YES)" = "true" ] && YES_FLAG="--yes"; \
	bash scripts/delete_api_key.sh "$(KEY_NAME)" $$YES_FLAG

dev:
	bash scripts/dev_uvicorn.sh

doctor:
	bash scripts/doctor.sh


