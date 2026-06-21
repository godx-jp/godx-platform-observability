# Dashboards

Drop Grafana dashboard JSON files here. They are auto-loaded by the bundled provider (`config/grafana/provisioning/dashboards/dashboards.yml`).

Recommended starter dashboards to import from grafana.com once needed:

| Dashboard | ID | Purpose |
|-----------|----|---------|
| Node Exporter Full | 1860 | Host metrics |
| OpenTelemetry Collector | 18309 | Collector health |
| Loki Logs / Operational | 13407 | Loki ops |
| Tempo Operational | 17848 | Tempo ops |
| RED Method per service | — | Build from `span-metrics` exposed by Tempo metrics generator |

Bundled: [`observability-overview.json`](./observability-overview.json) — span
rate/latency (from Tempo span-metrics in Mimir) + log volume/errors (Loki).

Naming convention: `kebab-case.json` — folders allowed (mirrored to Grafana folders).

**In production (Helm):** the umbrella chart ships `helm/dashboards/*.json` to
Grafana via the dashboard sidecar (ConfigMap labelled `grafana_dashboard=1`).
Add a JSON there and it is imported on the next `helm upgrade`. See
[`../helm/templates/grafana-dashboards.yaml`](../helm/templates/grafana-dashboards.yaml).
