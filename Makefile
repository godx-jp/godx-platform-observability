SHELL := /bin/bash

COMPOSE      ?= docker compose
COMPOSE_FILE ?= compose/docker-compose.yml
ENV_FILE     ?= .env

# All commands export the env file so ${VAR:-default} resolution works.
DC := $(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE)

.DEFAULT_GOAL := help

##@ General

help: ## Show this help
	@awk 'BEGIN{FS=":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_0-9-]+:.*?##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2} \
		/^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0,5)}' $(MAKEFILE_LIST)

version: ## Print bundle version
	@cat VERSION

##@ Lifecycle

up: ## Start full LGTM + OTel Collector stack
	$(DC) up -d
	@echo
	@echo "Grafana   → http://localhost:$${GRAFANA_HOST_PORT:-3000}"
	@echo "OTLP gRPC → localhost:$${OTLP_GRPC_HOST_PORT:-4317}"
	@echo "OTLP HTTP → localhost:$${OTLP_HTTP_HOST_PORT:-4318}"

up-lite: ## Start all-in-one grafana/otel-lgtm image (dev/CI light)
	$(COMPOSE) --env-file $(ENV_FILE) -f compose/docker-compose.otel-lgtm.yml up -d

down: ## Stop and remove containers
	$(DC) down

down-volumes: ## Stop and remove containers + volumes (DATA LOSS)
	$(DC) down -v

restart: down up ## Restart stack

ps: ## Container status
	$(DC) ps

logs: ## Tail logs from all services
	$(DC) logs -f --tail=100

logs-%: ## Tail logs from one service (e.g. make logs-grafana)
	$(DC) logs -f --tail=100 $*

##@ Operations

reload-prometheus: ## Hot-reload Prometheus config (no restart)
	curl -fsSL -X POST http://localhost:$${PROM_HOST_PORT:-9090}/-/reload && echo "reloaded"

health: ## Probe each backend
	@printf "Grafana: ";    curl -fsS http://localhost:$${GRAFANA_HOST_PORT:-3000}/api/health > /dev/null && echo OK || echo FAIL
	@printf "Prometheus: "; curl -fsS http://localhost:$${PROM_HOST_PORT:-9090}/-/healthy   > /dev/null && echo OK || echo FAIL
	@printf "OTLP HTTP: ";  curl -fsS -o /dev/null -w '%{http_code}\n' http://localhost:$${OTLP_HTTP_HOST_PORT:-4318}/v1/traces -X POST -H 'content-type: application/json' -d '{}'

##@ Validate

validate: ## Validate compose + config
	$(DC) config -q && echo "compose OK"
	$(COMPOSE) --env-file $(ENV_FILE) -f compose/docker-compose.otel-lgtm.yml config -q && echo "compose (otel-lgtm) OK"

##@ Helm (production / Kubernetes)

HELM        ?= helm
HELM_CHART  ?= helm
HELM_RELEASE ?= obs
HELM_NS     ?= observability
# Storage overlay: s3 | gcs | azure | minio
HELM_STORAGE ?= s3
HELM_VALUES := -f $(HELM_CHART)/values.yaml -f $(HELM_CHART)/values-$(HELM_STORAGE).yaml -f $(HELM_CHART)/values-production.yaml

helm-repos: ## Add upstream chart repos (grafana, open-telemetry)
	$(HELM) repo add grafana https://grafana.github.io/helm-charts
	$(HELM) repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	$(HELM) repo update

helm-deps: ## Resolve pinned chart dependencies into helm/charts/
	$(HELM) dependency build $(HELM_CHART)

helm-lint: ## Lint the umbrella chart with the production overlay set
	$(HELM) lint $(HELM_CHART) $(HELM_VALUES)

helm-template: ## Render manifests (dry-run) with the production overlay set
	$(HELM) template $(HELM_RELEASE) $(HELM_CHART) -n $(HELM_NS) $(HELM_VALUES)

helm-install: ## Install/upgrade the stack (set HELM_STORAGE=s3|gcs|azure|minio)
	$(HELM) upgrade --install $(HELM_RELEASE) $(HELM_CHART) -n $(HELM_NS) --create-namespace $(HELM_VALUES) --wait --timeout 15m

##@ Test

test: test-unit test-smoke ## Run unit + smoke tests

test-unit: ## Static validation: compose config, yamllint, backend config syntax
	./tests/unit.sh

test-smoke: ## End-to-end smoke: bring stack up, push telemetry, verify ingestion
	./tests/smoke.sh

test-smoke-down: ## Smoke + tear down after (KEEP=0)
	KEEP=0 ./tests/smoke.sh

.PHONY: help version up up-lite down down-volumes restart ps logs reload-prometheus health validate test test-unit test-smoke test-smoke-down \
	helm-repos helm-deps helm-lint helm-template helm-install
