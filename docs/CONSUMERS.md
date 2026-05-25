# Integration guide — for consumer projects

Pick the pattern that matches your environment.

## Pattern matrix

| Pattern | Lifecycle | Setup cost | Best for |
|---------|-----------|------------|----------|
| **A. Compose include** | Stack lifecycle == app lifecycle | Lowest | Single monorepo, demos, CI |
| **B. External network + overlay** | Stack runs independently, many apps share | Medium | Multiple projects on one laptop / VM |
| **C. Git submodule** | Pinned commit, vendored into project | Medium | Air-gapped or regulated environments |
| **D. Helm (production)** | Cluster lifecycle | High | Staging / production Kubernetes |

---

## A. Compose `include`

> Requires Docker Compose **v2.20+**. Stack containers come up/down with your app stack.

```yaml
# my-project/docker-compose.yml
name: my-project

include:
  - path: ../godx-platform-observability/compose/docker-compose.yml
    env_file: ../godx-platform-observability/.env

services:
  my-app:
    image: ghcr.io/example/my-app:1.0.0
    environment:
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
      OTEL_RESOURCE_ATTRIBUTES: service.name=my-app,service.version=1.0.0,deployment.environment=dev
    labels:
      observability.collect: "true"
      observability.service: "my-app"
      observability.env: "dev"
    networks:
      - default

networks:
  default:
    name: ${OBS_NETWORK:-observability}
```

```bash
docker compose up -d
open http://localhost:3000
```

See [examples/consumer-include/](../examples/consumer-include/).

---

## B. External network + overlay

> Stack runs once per machine; many app projects attach.

```bash
# 1. Run the plane (once)
cd godx-platform-observability/
cp .env.example .env
make up

# 2. From each app project — just attach to the network
cd ../my-project/
docker compose up -d
```

Consumer compose:

```yaml
services:
  my-app:
    environment:
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
    labels:
      observability.collect: "true"
      observability.service: "my-app"
      observability.env: "dev"
    networks:
      - observability

networks:
  observability:
    external: true
    name: ${OBS_NETWORK:-observability}
```

To have Prometheus scrape your `/metrics`, drop a target file:

```bash
cp examples/consumer-overlay/prometheus-scrape.yml \
   config/prometheus/scrape.d/my-project.yml
make reload-prometheus
```

See [examples/consumer-overlay/](../examples/consumer-overlay/).

---

## C. Git submodule

```bash
git submodule add -b main https://github.com/<org>/godx-platform-observability vendor/observability
git submodule update --init --recursive

# Pin to a release
cd vendor/observability && git checkout v0.1.0 && cd ../..
git add vendor/observability && git commit -m "Pin observability v0.1.0"
```

Then use Pattern A or B with `../vendor/observability/` paths.

Upgrade: bump the submodule pointer in a PR, run `make validate`, observe in Grafana.

---

## D. Production (Helm)

This repo ships **values overlays**; install upstream charts:

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# 1. OTel Collector gateway
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  -n observability --create-namespace \
  -f helm/values/otel-collector.values.yaml

# 2. Loki / Tempo / Mimir / Grafana
helm upgrade --install loki    grafana/loki              -n observability -f helm/values/loki.values.yaml
helm upgrade --install tempo   grafana/tempo-distributed -n observability -f helm/values/tempo.values.yaml
helm upgrade --install mimir   grafana/mimir-distributed -n observability -f helm/values/mimir.values.yaml
helm upgrade --install grafana grafana/grafana           -n observability -f helm/values/grafana.values.yaml
```

Apps in any namespace point at:

```
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability:4317
```

Cluster-wide log collection: deploy the OpenTelemetry Collector as a DaemonSet with the `filelog` receiver instead of Promtail.

See [helm/README.md](../helm/README.md) for the production roadmap.

---

## App instrumentation cheatsheet

| Language | Env vars |
|----------|----------|
| Any (OTel SDK) | `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317`<br>`OTEL_EXPORTER_OTLP_PROTOCOL=grpc`<br>`OTEL_RESOURCE_ATTRIBUTES=service.name=<svc>,deployment.environment=<env>` |
| Go (slog) | Use a JSON handler; include `trace_id` from `trace.SpanContextFromContext(ctx)` |
| Node (pino) | `pino({ formatters: { level: l => ({level: l}) } })` + `pino-opentelemetry-transport` |
| Python | `opentelemetry-instrument --logs_exporter otlp <cmd>` |
| Java | `-javaagent:opentelemetry-javaagent.jar` |

Full emission contract: [CONTRACT.md](./CONTRACT.md).

---

## Verification (90-second smoke test)

```bash
# 1. Stack is up
make ps
make health

# 2. Send a synthetic trace
docker run --rm --network ${OBS_NETWORK:-observability} \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318 \
  ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  traces --otlp-insecure --traces 5

# 3. Open Grafana → Explore → Tempo → TraceQL: { resource.service.name = "telemetrygen" }
```

If the trace shows up, every piece (Collector → Tempo → Grafana datasource → UI) is wired correctly.
