# Getting started

A five-minute tour from `git clone` to seeing your first trace in Grafana.

> Already know what this is? Skip to [step 1](#step-1--clone-and-bring-up). Want context? Read [OVERVIEW.md](./OVERVIEW.md) first (5 more minutes).

## Prerequisites

| Tool | Why |
|------|-----|
| Docker Desktop / Engine | Runs the stack |
| Docker Compose v2.20+ | Required for the `include` directive used in examples |
| `curl` | Probing the smoke endpoints |
| Browser | Grafana UI |

That's it. No language toolchain, no Helm, no Kubernetes — pure Docker.

---

## Step 1 — clone and bring up

```bash
git clone https://github.com/<org>/godx-platform-observability
cd godx-platform-observability
cp .env.example .env
make up
```

`make up` pulls images on first run (≈ 5 min on a fresh machine), then starts six containers: Grafana, Loki, Promtail, Prometheus, Tempo, OpenTelemetry Collector.

When the command returns:

```
Grafana   → http://localhost:3000
OTLP gRPC → localhost:4317
OTLP HTTP → localhost:4318
```

---

## Step 2 — log in to Grafana

Open <http://localhost:3000> in your browser.

| Login | Default |
|-------|---------|
| User  | `admin` |
| Pass  | `admin` |

You'll be asked to change the password — change it (or skip in dev). Land on the home dashboard.

Verify the three datasources were provisioned automatically: **Connections → Data sources** → you should see **Prometheus** (default), **Loki**, **Tempo**.

---

## Step 3 — send your first trace

This uses the official OpenTelemetry `telemetrygen` image — no application code needed.

```bash
docker run --rm --network observability \
  ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  traces \
  --otlp-endpoint otel-collector:4317 \
  --otlp-insecure \
  --service hello-world \
  --traces 10 \
  --rate 5 \
  --duration 3s
```

You just pushed 10 traces tagged `service.name=hello-world` to the OTel Collector, which forwarded them to Tempo.

---

## Step 4 — find the trace in Grafana

1. **Explore** (compass icon on the left rail).
2. Datasource dropdown (top-left) → **Tempo**.
3. Query type → **Search**. Service Name → `hello-world`. **Run query**.
4. A list of trace IDs appears — click one.
5. **Waterfall view** opens: spans with timing and attributes.

You've completed the inbound path: app → Collector → Tempo → Grafana.

---

## Step 5 — wire up a real application

Two integration patterns; pick one. Full guide: [CONSUMERS.md](./CONSUMERS.md).

### Pattern A — `compose include` (simplest)

In your project's `docker-compose.yml`:

```yaml
name: my-project

include:
  - path: ../godx-platform-observability/compose/docker-compose.yml
    env_file: ../godx-platform-observability/.env

services:
  my-app:
    image: ghcr.io/example/my-app:latest
    environment:
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
      OTEL_RESOURCE_ATTRIBUTES: service.name=my-app,service.version=1.0.0,deployment.environment=dev
    labels:
      observability.collect: "true"
      observability.service: "my-app"
      observability.env: "dev"
    networks: [default]

networks:
  default:
    name: observability
```

`docker compose up -d` — one command brings up both your app and the entire observability stack.

### Pattern B — external network (shared stack)

If the stack is already running (from this repo), your project just attaches to the network:

```yaml
services:
  my-app:
    environment:
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
    labels:
      observability.collect: "true"
      observability.service: "my-app"
    networks: [observability]

networks:
  observability:
    external: true
```

---

## Step 6 — make Prometheus scrape your app's `/metrics`

Drop a file in `config/prometheus/scrape.d/`:

```yaml
# config/prometheus/scrape.d/my-project.yml
- targets: ['my-app:8080']
  labels:
    service: my-app
    project: my-project
```

```bash
make reload-prometheus
```

Check **<http://localhost:9090/targets>** — your endpoint should show **UP**.

---

## Step 7 — query logs

If your app writes structured JSON logs to stdout with the labels from step 5, Promtail is already shipping them to Loki.

In Grafana **Explore** → **Loki**:

```logql
{service="my-app"} |= "error"
```

Click any log line: if it contains `trace_id`, a **TraceID** link appears that jumps straight to the Tempo trace view. End-to-end correlation in two clicks.

---

## Step 8 — verify everything works

```bash
make test-smoke
```

This brings up the stack (if not already), pushes synthetic telemetry, queries each backend, and verifies ingestion. Pass = the bundle is healthy on your machine.

---

## Where to next

| You want to… | Read |
|--------------|------|
| Understand the product surface (flow, screens, journeys) | [OVERVIEW.md](./OVERVIEW.md) |
| See every env var / port / label | [CONFIGURATION.md](./CONFIGURATION.md) |
| Make your app emit the right telemetry | [CONTRACT.md](./CONTRACT.md) |
| Integrate from a real consumer monorepo | [CONSUMERS.md](./CONSUMERS.md) |
| Run this in production | [../helm/README.md](../helm/README.md) |
| Understand the architecture choices | [ARCHITECTURE.md](./ARCHITECTURE.md) |
| Pin a version safely | [VERSIONING.md](./VERSIONING.md) |

---

## Cleanup

```bash
make down            # stop containers, keep data
make down-volumes    # stop containers AND wipe data (irreversible)
```
