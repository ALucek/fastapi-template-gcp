.PHONY: env-example env-examples api-key build-deploy gw-update init keys del-key dev doctor

ROOT := $(shell pwd)

env-example: env-examples

env-examples:
	@[ -f $(ROOT)/.env.infra ] || ( \
		if [ -f $(ROOT)/.env.infra.example ]; then \
			cp $(ROOT)/.env.infra.example $(ROOT)/.env.infra && echo ".env.infra created"; \
		else \
			echo "Missing $(ROOT)/.env.infra.example. Cannot create .env.infra." >&2; \
			exit 1; \
		fi \
	)
	@[ -f $(ROOT)/.env.app ] || ( \
		if [ -f $(ROOT)/.env.app.example ]; then \
			cp $(ROOT)/.env.app.example $(ROOT)/.env.app && echo ".env.app created"; \
		else \
			echo "Missing $(ROOT)/.env.app.example. Cannot create .env.app." >&2; \
			exit 1; \
		fi \
	)
	@[ -f $(ROOT)/.env.deploy ] || ( \
		if [ -f $(ROOT)/.env.deploy.example ]; then \
			cp $(ROOT)/.env.deploy.example $(ROOT)/.env.deploy && echo ".env.deploy created"; \
		else \
			echo "Missing $(ROOT)/.env.deploy.example. Cannot create .env.deploy." >&2; \
			exit 1; \
		fi \
	)

api-key:
	PREFIX="$(PREFIX)" KEY_PREFIX="$(KEY_PREFIX)" PRINT_KEY="$(PRINT_KEY)" bash scripts/create_api_key.sh

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
	YES="$(YES)" bash scripts/delete_api_key.sh "$(KEY_NAME)"

dev:
	bash scripts/dev_uvicorn.sh

doctor:
	bash scripts/doctor.sh


