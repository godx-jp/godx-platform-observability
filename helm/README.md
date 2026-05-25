# Production deployment (Kubernetes)

This repo's `compose/` is dev-grade. For production use upstream **Helm charts**:

| Component | Chart |
|-----------|-------|
| OpenTelemetry Collector | [`open-telemetry/opentelemetry-collector`](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-collector) (gateway) + `opentelemetry-kube-stack` (DaemonSet) |
| Logs | [`grafana/loki`](https://github.com/grafana/loki/tree/main/production/helm/loki) (distributed mode) |
| Metrics | [`grafana/mimir-distributed`](https://github.com/grafana/mimir/tree/main/operations/helm/charts/mimir-distributed) |
| Traces | [`grafana/tempo-distributed`](https://github.com/grafana/tempo/tree/main/operations/helm/charts/tempo-distributed) |
| UI | [`grafana/grafana`](https://github.com/grafana/helm-charts/tree/main/charts/grafana) |

## Repo role

`helm/values/` holds **opinionated value overlays** — what differentiates our deployment from upstream defaults (object storage backend, retention, tenant config, scrape rules).

```
helm/values/
├── otel-collector.values.yaml
├── loki.values.yaml
├── tempo.values.yaml
├── mimir.values.yaml
└── grafana.values.yaml
```

(Files will be added per environment as needed.)

## Status

Production overlays are **not yet generated**. Roadmap order:

1. **OTel Collector** gateway + DaemonSet → confirm OTLP ingest works against dev backends.
2. **Loki** distributed + S3 (MinIO / R2) storage.
3. **Tempo** distributed + S3.
4. **Mimir** to replace single-node Prometheus.
5. **Grafana** with SSO + provisioned datasources.

## GitOps integration

When values are added, recommend wiring with **Argo CD** or **Flux**:

```yaml
# Argo CD Application example
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: observability
  namespace: argocd
spec:
  project: platform
  destination:
    namespace: observability
    server: https://kubernetes.default.svc
  source:
    repoURL: https://github.com/<org>/godx-platform-observability
    targetRevision: v0.1.0
    path: helm/values
```

## Why not ship a custom umbrella chart?

A handwritten meta-chart adds maintenance with no upside vs. five `helm upgrade --install` lines + GitOps app-of-apps. Industry best practice is to compose upstream charts via values, not fork them.

## See also

- [Consumer guide — pattern D](../docs/CONSUMERS.md#d-production-helm)
- [Architecture](../docs/ARCHITECTURE.md)
