# Emission contract

What every application MUST emit to be a first-class citizen of the observability plane. Language-agnostic; pick the appropriate SDK.

## TL;DR

| Signal | Required | Endpoint | Format |
|--------|----------|----------|--------|
| Traces | ✅ | `${OTEL_EXPORTER_OTLP_ENDPOINT}` | OTLP gRPC or HTTP |
| Metrics | ✅ | OTLP push **or** `/metrics` scrape | OpenMetrics |
| Logs | ✅ | stdout (Promtail-collected) **or** OTLP | Structured JSON |

`OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317` (gRPC) or `:4318` (HTTP).

## Resource attributes (mandatory)

Set once at process start (env var works for every OTel SDK):

```bash
OTEL_RESOURCE_ATTRIBUTES=service.name=<svc>,service.version=<ver>,deployment.environment=<env>
```

| Key | Required | Notes |
|-----|----------|-------|
| `service.name` | ✅ | Stable; becomes Loki label `service`, Prom label `service` (via Collector), Tempo span resource |
| `service.version` | ✅ | Semver string |
| `deployment.environment` | ✅ | `dev` \| `staging` \| `prod` |
| `service.namespace` | optional | Use for bounded context (`commerce`, `logistics`, …) |
| `service.instance.id` | optional | Pod name / container ID; SDK usually fills it |

Follow [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/) — no custom keys without a clear reason.

## Logs

### Output

- **Where**: process stdout, one JSON object per line.
- **Why JSON**: Promtail + Loki structured metadata; downstream queries can filter by field.

### Required fields

```json
{
  "ts": "2026-05-25T05:00:00.123Z",
  "level": "info",
  "msg": "request handled",
  "service": "my-app",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7"
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `ts` | ✅ | ISO 8601 / RFC 3339 |
| `level` | ✅ | `debug` `info` `warn` `error` |
| `msg` | ✅ | Short human message |
| `service` | ✅ | Match `service.name` |
| `trace_id` | when in span | Hex (W3C trace-id); enables Loki ↔ Tempo correlation |
| `span_id` | when in span | Hex |
| `correlation_id` | when applicable | App-level request id |

Loki's derived-field rule lifts `trace_id` to a clickable link → Tempo.

### Pipeline choice

| Choice | When |
|--------|------|
| stdout → Promtail (Docker socket) | Default. Zero app code beyond JSON logger. Label container with `observability.collect=true`. |
| OTLP logs exporter (app pushes directly) | Recommended for K8s and for apps that already use the OTel SDK end-to-end. |

## Metrics

| Choice | When |
|--------|------|
| Expose `/metrics` (OpenMetrics) | Default for Go/Java/Python with a Prom client lib. Register the target in `config/prometheus/scrape.d/<project>.yml`. |
| OTLP push via Collector | When scraping is impractical (short-lived jobs, NAT, batch). Collector remote-writes to Prometheus. |

Naming follows [Prometheus naming](https://prometheus.io/docs/practices/naming/):

```
http_server_requests_total{method, route, status}
http_server_request_duration_seconds_bucket{method, route, le}
db_pool_in_use{pool}
```

Avoid high-cardinality labels (`user_id`, `request_id`, raw URLs). Use exemplars to attach `trace_id` to histograms.

## Traces

- Use the language's OTel SDK; auto-instrumentation where available.
- Propagate W3C `traceparent` / `tracestate` headers on every outbound HTTP/gRPC call.
- Span names: low-cardinality (`GET /users/{id}`, not `/users/123`).
- Set status correctly on errors; record exceptions.

## What apps MUST NOT do

| Anti-pattern | Use instead |
|--------------|-------------|
| Write logs to disk inside the container | stdout |
| Ship logs to a per-service ELK | OTel/Promtail → Loki |
| Bundle Prometheus/Grafana in their own image | Consume the shared plane |
| Hard-code `loki:3100` / `tempo:4317` | Only `otel-collector:4317`/`4318`; backends may swap |
| Put unbounded labels on metrics | High cardinality → Prom OOM |

## Drop-in libraries

| Language | Library |
|----------|---------|
| Go | `go.opentelemetry.io/otel` + `log/slog` JSON handler (wrap once in your own `pkg/observability`) |
| Node | `@opentelemetry/sdk-node` + `pino` w/ JSON transport |
| Python | `opentelemetry-distro` + `structlog` |
| Java | `opentelemetry-javaagent` (auto-instrumentation) |
| Rust | `tracing` + `tracing-opentelemetry` + `tracing-subscriber` (JSON) |
