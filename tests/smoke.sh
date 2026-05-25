#!/usr/bin/env bash
# End-to-end smoke test: bring up the stack, push synthetic telemetry,
# verify each backend ingested it.
#
# Usage:
#   ./tests/smoke.sh           # bring up, test, leave running
#   KEEP=0 ./tests/smoke.sh    # tear down after
#
# Requires: docker, curl, jq

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=tests/lib/assert.sh
source tests/lib/assert.sh

KEEP="${KEEP:-1}"
ENV_FILE="${ENV_FILE:-.env}"
COMPOSE_FILE="${COMPOSE_FILE:-compose/docker-compose.yml}"
DC=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

# Load env (ports, network name, image pins).
[[ -f "$ENV_FILE" ]] || cp .env.example "$ENV_FILE"
set -a; source "$ENV_FILE"; set +a

cleanup() {
  if [[ "$KEEP" == "0" ]]; then
    step "Tearing down (KEEP=0)"
    "${DC[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  else
    echo
    echo "(stack left running — \`make down\` to stop)"
  fi
  summary
}
trap cleanup EXIT

# ─── 1. Bring up ────────────────────────────────────────────────────────────
step "Starting the stack"
"${DC[@]}" up -d >/dev/null
pass "compose up"

# ─── 2. Wait for backends to be healthy ─────────────────────────────────────
step "Waiting for backends"
wait_http "http://localhost:${GRAFANA_HOST_PORT:-3000}/api/health" 90 "Grafana"
wait_http "http://localhost:${PROM_HOST_PORT:-9090}/-/healthy"     60 "Prometheus"

# Collector / Loki / Tempo aren't host-exposed → probe from inside the network.
docker_exec_curl() { docker run --rm --network "${OBS_NETWORK:-observability}" curlimages/curl:8.10.1 "$@"; }

if docker_exec_curl -fsS -o /dev/null -m 5 http://otel-collector:13133/ >/dev/null 2>&1; then
  pass "OTel Collector health"
else
  # Retry loop because Collector starts after Loki/Tempo on slow machines.
  ok=0
  for _ in $(seq 1 30); do
    if docker_exec_curl -fsS -o /dev/null -m 5 http://otel-collector:13133/ >/dev/null 2>&1; then
      ok=1; break
    fi
    sleep 2
  done
  [[ $ok -eq 1 ]] && pass "OTel Collector health (retry)" || fail "OTel Collector health"
fi

assert_cmd "Loki ready"  docker_exec_curl -fsS -m 5 http://loki:3100/ready
assert_cmd "Tempo ready" docker_exec_curl -fsS -m 5 http://tempo:3200/ready

# ─── 3. Push synthetic telemetry via OpenTelemetry telemetrygen ─────────────
step "Pushing synthetic traces via telemetrygen"
SVC="smoke-test-$$"
docker run --rm --network "${OBS_NETWORK:-observability}" \
  ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  traces \
  --otlp-endpoint otel-collector:4317 \
  --otlp-insecure \
  --service "$SVC" \
  --traces 5 \
  --rate 5 \
  --duration 2s >/dev/null
pass "telemetrygen sent 5 traces (service.name=$SVC)"

# Tempo's WAL flush + indexer lag ~5-15s on first run.
step "Verifying ingestion (allow up to 30s)"
ok=0
for _ in $(seq 1 15); do
  body=$(docker_exec_curl -fsS -m 5 "http://tempo:3200/api/search?tags=service.name=$SVC" 2>/dev/null || echo '')
  if [[ "$body" == *"\"traceID\""* || "$body" == *"\"traces\""* ]]; then
    ok=1; break
  fi
  sleep 2
done
[[ $ok -eq 1 ]] && pass "Tempo received traces for $SVC" || fail "Tempo did not see traces for $SVC"

# ─── 4. Verify Prometheus is scraping OTel Collector self-metrics ───────────
step "Verifying Prometheus scrape of otel-collector"
body=$(docker_exec_curl -fsS -m 5 "http://prometheus:9090/api/v1/query?query=up%7Bjob%3D%22otel-collector%22%7D" || echo '')
assert_contains "prometheus scrape otel-collector" "$body" '"value":'

# ─── 5. Verify Grafana provisioned datasources ──────────────────────────────
step "Verifying Grafana datasource provisioning"
ds=$(curl -fsS -u "${GRAFANA_ADMIN_USER:-admin}:${GRAFANA_ADMIN_PASSWORD:-admin}" \
  "http://localhost:${GRAFANA_HOST_PORT:-3000}/api/datasources" || echo '[]')
assert_contains "Prometheus datasource present" "$ds" '"type":"prometheus"'
assert_contains "Loki datasource present"        "$ds" '"type":"loki"'
assert_contains "Tempo datasource present"       "$ds" '"type":"tempo"'
