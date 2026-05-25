# godx-platform-observability

> **A standalone observability product by godx** — a vendor-neutral, self-hosted alternative to AWS CloudWatch / Datadog, built on Grafana LGTM + OpenTelemetry.
> Drop into **any** project, any stack, any team.

[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](./CHANGELOG.md)
[![License](https://img.shields.io/badge/license-Apache_2.0-green.svg)](./LICENSE)
[![Maintainer](https://img.shields.io/badge/by-godx-black.svg)](#)

## Who is this for

Any team that wants centralized **logs · metrics · traces** without the per-project setup tax.

| You have… | This gives you… |
|-----------|-----------------|
| One service, one Docker host | A 1-command observability backend on `localhost:3000` |
| A microservice monorepo | A shared plane all services emit to — no per-repo Loki/Grafana |
| Many independent projects | One stack per machine; every project just attaches to the network |
| A Kubernetes cluster | A values overlay over upstream Helm charts (no fork) |

It does **not assume** a specific framework, language, cloud, or consumer. **Zero project-specific code.**

```text
   Any project (apps, infra)
            │  OTLP :4317 / :4318       (logs, metrics, traces)
            ▼
   ┌──────────────────────┐
   │  OpenTelemetry       │  single ingress — apps know ONE endpoint
   │  Collector (gateway) │
   └─┬──────┬──────┬──────┘
     ▼      ▼      ▼
   Loki   Prom*  Tempo            *Prometheus dev / Mimir prod
     │      │      │
     └──────┴──────┴──► Grafana (UI, dashboards, alerts)
```

## What this is

A **deploy + config bundle** you drop into any project to get a complete observability backend:

- **Logs** → Loki (label-based, CloudWatch-log-group-equivalent)
- **Metrics** → Prometheus (or Mimir in prod)
- **Traces** → Tempo (OTLP gRPC + HTTP)
- **Ingest gateway** → OpenTelemetry Collector — the **only** endpoint apps need to know
- **UI** → Grafana with datasources pre-wired (logs ↔ traces ↔ metrics correlated)

What it is **not**: a fork of Grafana / Loki / Tempo. We pin upstream images + ship opinionated config, versioned with semver.

## Quick start

```bash
git clone <this-repo> godx-platform-observability
cd godx-platform-observability
cp .env.example .env
make up
open http://localhost:3000        # Grafana (admin / admin by default — change .env)
```

**New here?** Start with [docs/GETTING_STARTED.md](./docs/GETTING_STARTED.md) (5-min walk-through) or [docs/OVERVIEW.md](./docs/OVERVIEW.md) (the product tour — flow, screens, journeys).

Send a test trace:

```bash
docker run --rm --network observability \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318 \
  ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
  traces --otlp-insecure --traces 5
```

## Use from another project

Three patterns — pick one. Full guide: [docs/CONSUMERS.md](./docs/CONSUMERS.md).

### 1. Compose `include` (recommended for monorepos)

```yaml
# your-project/docker-compose.yml
include:
  - path: ../godx-platform-observability/compose/docker-compose.yml
    env_file: ../godx-platform-observability/.env

services:
  my-app:
    environment:
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317
    networks: [observability]

networks:
  observability:
    external: true
    name: ${OBS_NETWORK:-observability}
```

### 2. Git submodule

```bash
git submodule add https://github.com/your-org/godx-platform-observability vendor/observability
```

### 3. Production (Kubernetes)

Use upstream Helm charts; this repo ships **values overlays** under `helm/`. See [helm/README.md](./helm/README.md).

## Two flavours

| Flavour | File | When |
|---------|------|------|
| **Multi-container (default)** | `compose/docker-compose.yml` | Mirrors prod topology — separate Loki, Prom, Tempo, Grafana, OTel Collector. Recommended. |
| **All-in-one** | `compose/docker-compose.otel-lgtm.yml` | Single upstream `grafana/otel-lgtm` image. Lighter on the laptop. Dev/CI/demo only. |

## Repository layout

```
godx-platform-observability/
├── compose/                  # docker-compose stacks
├── config/                   # tunable backend config
│   ├── loki/  promtail/  prometheus/  tempo/
│   ├── otel-collector/       # OTLP gateway routing
│   └── grafana/provisioning/ # datasources + dashboard provider
├── dashboards/               # JSON dashboards (RED, USE, infra)
├── examples/                 # consumer integration patterns
├── helm/                     # prod K8s overlay values
├── tests/                    # static + smoke (pure bash, no extra runner)
│   ├── unit.sh               # compose config + yamllint + backend config syntax
│   ├── smoke.sh              # bring up + telemetrygen + verify ingestion
│   └── lib/assert.sh         # tiny assertion helpers
└── docs/
    ├── OVERVIEW.md           # product overview, end-to-end flow, UI screens, user journeys
    ├── GETTING_STARTED.md    # 5-min tutorial: clone → first trace → wire your app
    ├── ARCHITECTURE.md       # plane design, signal flow, components
    ├── CONTRACT.md           # what apps MUST emit (log fields, OTel attrs)
    ├── CONFIGURATION.md      # every env var, port, Docker label, override path
    ├── CONSUMERS.md          # full integration guide (4 patterns)
    └── VERSIONING.md         # semver + compatibility matrix
```

## Versioning

Semver tags (`v0.1.0`, `v0.2.0`, …). Consumers pin a tag. Breaking changes documented in [CHANGELOG.md](./CHANGELOG.md). Policy: [docs/VERSIONING.md](./docs/VERSIONING.md).

## Ports

| Service | Internal | Default host map (dev) |
|---------|----------|-------------------------|
| Grafana | 3000 | `${GRAFANA_HOST_PORT:-3000}` |
| OTel Collector OTLP gRPC | 4317 | `${OTLP_GRPC_HOST_PORT:-4317}` |
| OTel Collector OTLP HTTP | 4318 | `${OTLP_HTTP_HOST_PORT:-4318}` |
| Prometheus | 9090 | `${PROM_HOST_PORT:-9090}` |
| Loki | 3100 | not exposed by default (push via Promtail/OTel) |
| Tempo HTTP | 3200 | not exposed by default |

Override in `.env`. Production: don't expose internal ports — front with reverse proxy / Ingress.

## What apps MUST emit

Single contract — language-agnostic. Full spec: [docs/CONTRACT.md](./docs/CONTRACT.md).

| Signal | How |
|--------|-----|
| Logs | Structured JSON on stdout with `trace_id`, `level`, `service.name` |
| Metrics | OpenMetrics `/metrics` endpoint **or** push via OTLP |
| Traces | OTLP exporter → `${OTEL_EXPORTER_OTLP_ENDPOINT}` |

`OTEL_RESOURCE_ATTRIBUTES=service.name=<svc>,service.version=<ver>,deployment.environment=<env>`

## Tests

```bash
make test-unit         # static: compose config, yamllint, backend config syntax — no containers
make test-smoke        # e2e: bring up, push telemetry via OTel telemetrygen, verify ingestion
make test              # both
```

CI runs `unit` on every PR and `smoke` on push to `main` (`.github/workflows/validate.yml`). See [tests/README.md](./tests/README.md).

## Project status

- **Maintainer:** godx — this repo is the canonical, single-source-of-truth observability bundle.
- **License:** Apache 2.0 — free for internal and external use.
- **Stability:** `0.x` — pin to exact tag in production until `1.0.0`.
- **Scope:** packaging + opinionated config only. No forks of upstream components.

## License

Apache 2.0 — see [LICENSE](./LICENSE).
