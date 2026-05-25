# Configuration reference

Every knob you can turn — environment variables, ports, network, Docker labels.

> Source of truth: [`.env.example`](../.env.example). This document explains each entry, the consumer side (what apps set), and the Docker label contract used by the log shipper.

---

## 1. Environment variables — plane side (`.env`)

Copy `.env.example` → `.env` and edit. Loaded automatically by `make` and by `docker compose --env-file`.

### 1.1 Image pins

Bump these to upgrade a component. SemVer impact documented in [VERSIONING.md](./VERSIONING.md).

| Variable | Default | Purpose | Notes |
|----------|---------|---------|-------|
| `LOKI_IMAGE` | `grafana/loki:3.3.0` | Logs backend | Loki 3.x required for OTLP-native logs |
| `PROMTAIL_IMAGE` | `grafana/promtail:3.3.0` | Docker log shipper | Match Loki minor version |
| `PROMETHEUS_IMAGE` | `prom/prometheus:v2.55.1` | Metrics scrape + TSDB | `--web.enable-remote-write-receiver` required |
| `TEMPO_IMAGE` | `grafana/tempo:2.6.1` | Traces backend | Pinned — schema migrations are not automatic across majors |
| `GRAFANA_IMAGE` | `grafana/grafana:11.4.0` | UI | Datasource UIDs assume Grafana ≥ 10 |
| `OTELCOL_IMAGE` | `otel/opentelemetry-collector-contrib:0.115.1` | OTLP gateway | `-contrib` distribution required (Loki/Prom-RW exporters) |
| `OTEL_LGTM_IMAGE` | `grafana/otel-lgtm:0.8.5` | All-in-one (alt flavour) | Used by `compose/docker-compose.otel-lgtm.yml` only |

### 1.2 Network

| Variable | Default | Purpose |
|----------|---------|---------|
| `OBS_NETWORK` | `observability` | Docker network name. Consumers reference this in their compose with `external: true`. |
| `OBS_NETWORK_EXTERNAL` | `false` | `true` → compose expects the network to already exist (pre-create with `docker network create $OBS_NETWORK`). `false` → compose creates and owns it. |

### 1.3 Host port mapping (development)

Only the ingress (Grafana, OTLP, Prometheus) is exposed by default. Loki and Tempo stay internal — access them via Grafana.

| Variable | Default | Mapped from | Used by |
|----------|---------|-------------|---------|
| `GRAFANA_HOST_PORT` | `3000` | grafana:3000 | Browser → Grafana UI |
| `PROM_HOST_PORT` | `9090` | prometheus:9090 | Debug UI, `make reload-prometheus`, smoke tests |
| `OTLP_GRPC_HOST_PORT` | `4317` | otel-collector:4317 | App OTLP gRPC exporters running on the host |
| `OTLP_HTTP_HOST_PORT` | `4318` | otel-collector:4318 | App OTLP HTTP exporters / curl |
| `LOKI_HOST_PORT` | _(unmapped)_ | loki:3100 | Optional debug; uncomment in `.env.example` |
| `TEMPO_HTTP_HOST_PORT` | _(unmapped)_ | tempo:3200 | Optional debug |

**Production**: do not expose Loki, Tempo, or Prometheus directly. Front everything with Grafana + a reverse proxy / Ingress.

### 1.4 Grafana auth

| Variable | Default | Notes |
|----------|---------|-------|
| `GRAFANA_ADMIN_USER` | `admin` | Initial admin login |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | **Change for any non-laptop deployment** |
| `GRAFANA_ROOT_URL` | `http://localhost:3000/` | Set to the public URL when behind a reverse proxy (affects link generation in alerts) |
| `GRAFANA_ANONYMOUS_ENABLED` | `false` | `true` → no login form, anonymous = Admin role. **Dev convenience only — never enable in production or any network-exposed environment.** |

### 1.5 Retention

| Variable | Default | Component | Format |
|----------|---------|-----------|--------|
| `LOKI_RETENTION` | `720h` (30 d) | Loki | Go `time.Duration` (must be hours: `h`) |
| `PROM_RETENTION` | `30d` | Prometheus | Prometheus duration (`30d`, `90d`, `1y`) |
| `TEMPO_RETENTION` | `168h` (7 d) | Tempo (compactor `block_retention`) | Go `time.Duration` |

Increase with care — disk usage scales linearly. For prod, switch to object storage instead of bumping retention on local volumes.

### 1.6 Resource enrichment

| Variable | Default | Purpose |
|----------|---------|---------|
| `DEPLOYMENT_ENV` | `dev` | Value of `deployment.environment` resource attribute. Injected by OTel Collector and used as a Prometheus `external_labels` value. |

---

## 2. Environment variables — consumer side (apps)

What you set inside your application containers.

| Variable | Required | Example | Why |
|----------|----------|---------|-----|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | ✅ | `http://otel-collector:4317` (gRPC) or `http://otel-collector:4318` (HTTP) | OTel SDKs read this to know where to push traces, metrics, logs |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | optional | `grpc` (default) or `http/protobuf` | Disambiguate when both endpoints look possible |
| `OTEL_RESOURCE_ATTRIBUTES` | ✅ | `service.name=my-app,service.version=1.0.0,deployment.environment=dev` | Drives labels in Loki, Prom, Tempo and the Grafana service map |
| `OTEL_TRACES_SAMPLER` | optional | `parentbased_traceidratio` | Sampling policy (see OTel SDK docs) |
| `OTEL_TRACES_SAMPLER_ARG` | optional | `0.1` | Sample 10 % of traces |
| `OTEL_LOG_LEVEL` | optional | `info` | SDK internal log level — useful when debugging missing telemetry |

Full emission contract: [CONTRACT.md](./CONTRACT.md). Reference list of OTel env vars: [opentelemetry.io/docs/specs/otel/configuration/sdk-environment-variables](https://opentelemetry.io/docs/specs/otel/configuration/sdk-environment-variables/).

---

## 3. Docker labels — consumer container contract

Promtail's Docker discovery is **opt-in**: containers must announce themselves with labels. Apps that emit logs over OTLP directly do not need these.

| Label | Required | Example | Effect |
|-------|----------|---------|--------|
| `observability.collect` | ✅ (to ship logs via Promtail) | `"true"` | Without it, Promtail ignores the container |
| `observability.service` | ✅ | `"my-app"` | Becomes Loki label `service` |
| `observability.env` | optional | `"dev"` | Becomes Loki label `env` |

Example fragment for a consumer compose file:

```yaml
services:
  my-app:
    labels:
      observability.collect: "true"
      observability.service: "my-app"
      observability.env: "${DEPLOYMENT_ENV:-dev}"
```

Auto-derived Loki labels (no consumer action needed):

| Label | Source |
|-------|--------|
| `container` | Docker container name |
| `stream` | `stdout` / `stderr` |
| `project` | Docker Compose project name (`com.docker.compose.project`) |
| `level` | Parsed from JSON log body (if the field is named `level`) |

`trace_id` / `correlation_id` are parsed from JSON logs as **structured metadata** (Loki 3), not labels — keeps cardinality bounded.

---

## 4. File paths consumers may bind-mount

If a consumer needs to override one file without rebuilding the bundle, mount it on top:

| Path | Purpose | Override risk |
|------|---------|---------------|
| `config/prometheus/prometheus.yml` | Full Prometheus config | High — easier to use `scrape.d/*.yml` instead |
| `config/prometheus/scrape.d/<project>.yml` | Drop-in scrape target | None — file_sd, hot-reloaded |
| `config/otel-collector/config.yaml` | Collector pipeline | Medium — re-test smoke after edit |
| `config/grafana/provisioning/datasources/datasources.yml` | Datasource definitions | High — `serviceMap` / derived-field UIDs are referenced in dashboards |
| `dashboards/*.json` | Provisioned dashboards | None — drop in and Grafana picks up within 30 s |

---

## 5. Defaults summary

```bash
# Quick view of effective defaults (assumes you copied .env.example to .env unchanged)
make help          # commands
make version       # bundle version
make health        # ping every host-exposed endpoint
```

---

## 6. Production-only knobs (not in `.env.example`)

These belong in your Helm `values.yaml` rather than this dev `.env`. Listed here so you know they exist.

| Concern | Where to set |
|---------|--------------|
| Object-storage backend (S3 / GCS / Azure Blob / MinIO) | Loki `storage_config`, Tempo `storage.trace.s3`, Mimir `blocks_storage.backend` |
| Multi-tenant isolation | Loki `auth_enabled: true`, Tempo per-tenant overrides, Mimir `tenant_id`; Grafana datasource `httpHeaderName1: X-Scope-OrgID` |
| TLS termination | Reverse proxy / Ingress in front of Grafana; OTel Collector receivers can also do mTLS |
| Authn / SSO | Grafana `auth.generic_oauth`, `auth.oauth_auto_login` |
| Rule files | Prometheus `rule_files:` block (recording + alerting rules in Git) |
| Alertmanager (separate, optional) | Grafana ships its own; Prometheus rules can route to an external Alertmanager via remote_write or via Grafana contact point |
