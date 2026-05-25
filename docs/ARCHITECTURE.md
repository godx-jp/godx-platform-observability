# Architecture

## Goals

1. **Vendor-neutral observability as a product** — usable by any team, any project, any stack. No consumer is privileged.
2. **One observability plane per environment**, shared by every project — not per-project log/metrics stacks.
3. **One ingress contract**: apps emit OTLP; backends are swappable.
4. **Dev/prod parity**: same component split locally and in Kubernetes; only persistence and scale differ.
5. **No code in the plane**: off-the-shelf upstream images, opinionated config, semver-tagged bundle.

## Components

| Layer | Dev (this repo) | Prod (Helm overlay) | Owner |
|-------|-----------------|---------------------|-------|
| Ingest gateway | `otel/opentelemetry-collector-contrib` | OpenTelemetry Operator + DaemonSet + gateway Deployment | Platform / SRE |
| Logs | `grafana/loki` (filesystem) | `grafana/loki` distributed mode + S3/GCS | Platform / SRE |
| Metrics | `prom/prometheus` (TSDB) | `grafana/mimir-distributed` + object storage | Platform / SRE |
| Traces | `grafana/tempo` (filesystem) | `grafana/tempo-distributed` + S3/GCS | Platform / SRE |
| UI | `grafana/grafana` | `grafana/grafana` (HA) | Platform / SRE |
| Log shipper (optional) | `grafana/promtail` (Docker socket) | OTel Collector logs receiver per pod | Platform / SRE |

## Signal flow

```
┌──────── Application (any language) ────────┐
│  OTel SDK / structured logger (slog/…)     │
│  service.name, service.version, env attrs  │
└──────────────────┬─────────────────────────┘
                   │ OTLP gRPC :4317 / HTTP :4318
                   ▼
        ┌──────────────────────────┐
        │  OpenTelemetry Collector │  (gateway)
        │  - memory_limiter        │
        │  - resource enrich       │
        │  - batch                 │
        └─────┬────────┬───────┬──┘
              │        │       │
       logs   │ metrics│traces │
              ▼        ▼       ▼
            Loki    Prom    Tempo
              \      |      /
               \     |     /
                ▼    ▼    ▼
                 Grafana
        (TraceID derived field → Tempo)
        (tracesToLogsV2 → Loki)
        (serviceMap → Prometheus)
```

## Why a Collector gateway

- **One endpoint** for apps. Swap Loki↔Mimir↔Tempo without redeploying apps.
- **Backpressure** (`memory_limiter`) protects backends.
- **Resource enrichment** — inject `deployment.environment`, `cluster`, `tenant` server-side.
- **Sampling** — head/tail sampling policies live in the Collector, not in app code.
- **Future**: tail-based sampling, multi-tenant routing (`X-Scope-OrgID`), redaction.

## Multi-tenancy

Single-tenant by default. To turn on:

1. Loki: set `auth_enabled: true` + run multi-tenant.
2. Mimir/Tempo: enable per-tenant overrides.
3. Collector: add `processor: tenant_id` from a header.
4. Grafana: per-org datasource with `httpHeaderName1: X-Scope-OrgID`.

Document tenant naming convention per deployment (suggested: `<project>-<env>`).

## Persistence

| Env | Storage | Why |
|-----|---------|-----|
| Dev | Docker named volume | Survives `docker compose restart`, lost on `down -v`. Good enough. |
| Staging | Volume + nightly backup | Catch regressions; cheap. |
| Prod | Object store (S3/GCS/MinIO) | All three backends support it natively; required for horizontal scale. |

## Network model

- All containers join the network named `${OBS_NETWORK}` (default `observability`).
- Consumers attach as `external: true`; the plane creates and owns the network when run standalone.
- No host-level dependencies. Apps reach the gateway by service name `otel-collector`.

## What's intentionally NOT here

| Excluded | Why |
|----------|-----|
| ELK / Elasticsearch | Operational cost; Loki + OTel is the modern path. |
| Jaeger | Tempo + Grafana cover the same use cases natively. |
| Custom Dockerfile that bundles multiple daemons | Anti-pattern (one process per container). For dev all-in-one, use upstream `grafana/otel-lgtm`. |
| Application code | This is a deploy bundle, not a service. |
| Per-project forks of this repo | Use semver tags + `.env` to vary behaviour. |
