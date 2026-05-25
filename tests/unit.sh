#!/usr/bin/env bash
# Static validation — no containers brought up. Safe to run anywhere with docker.
#
# Usage: ./tests/unit.sh
# Targets:
#   - docker compose config (main + lite + examples)
#   - YAML lint (if yamllint present)
#   - Backend config syntax (loki, prometheus, tempo) via official images

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=tests/lib/assert.sh
source tests/lib/assert.sh

ENV_FILE="${ENV_FILE:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  cp .env.example "$ENV_FILE"
  warn "$ENV_FILE not found — created from .env.example"
fi

# Load image pins from the env file for the backend-check steps below.
set -a; source "$ENV_FILE"; set +a

step "Compose: config syntax"
assert_cmd "main compose"        docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml             config -q
assert_cmd "otel-lgtm compose"   docker compose --env-file "$ENV_FILE" -f compose/docker-compose.otel-lgtm.yml   config -q
assert_cmd "example: include"    docker compose --env-file "$ENV_FILE" -f examples/consumer-include/docker-compose.yml config -q
assert_cmd "example: overlay"    docker compose --env-file "$ENV_FILE" -f examples/consumer-overlay/docker-compose.yml config -q

step "YAML lint"
if command -v yamllint >/dev/null 2>&1; then
  if yamllint -d '{extends: default, rules: {line-length: disable, comments-indentation: disable, document-start: disable, truthy: disable, indentation: {indent-sequences: consistent}}}' config/ >/dev/null 2>&1; then
    pass "config/ yamllint"
  else
    fail "config/ yamllint (run: yamllint config/)"
  fi
else
  warn "yamllint not installed — skipping"
fi

step "Backend config syntax"
assert_cmd "loki -verify-config" \
  docker run --rm -v "$ROOT/config/loki:/etc/loki:ro" -e LOKI_RETENTION=720h \
    "${LOKI_IMAGE:-grafana/loki:3.3.0}" \
    -config.file=/etc/loki/loki-config.yml -config.expand-env=true -verify-config

assert_cmd "promtool check" \
  docker run --rm --entrypoint promtool \
    -v "$ROOT/config/prometheus:/etc/prometheus:ro" \
    "${PROMETHEUS_IMAGE:-prom/prometheus:v2.55.1}" \
    check config /etc/prometheus/prometheus.yml

assert_cmd "tempo -config.verify" \
  docker run --rm -v "$ROOT/config/tempo/tempo.yml:/etc/tempo.yml:ro" \
    "${TEMPO_IMAGE:-grafana/tempo:2.6.1}" \
    -config.file=/etc/tempo.yml -config.verify=true

summary
