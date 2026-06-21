# Production deployment — Kubernetes (Helm)

The repo's `compose/` stacks are single-node (monolithic Loki/Tempo, one
Prometheus, Grafana on SQLite) — perfect for dev and moderate load, but **not**
horizontally scalable. For production this directory ships an **umbrella Helm
chart** that composes the upstream Grafana + OpenTelemetry charts as
**values overlays — no forks**. You get "install and run" ergonomics:
`helm dependency build` then `helm upgrade --install`.

> Philosophy: we never fork upstream. Every component below is the unmodified
> upstream chart, version-pinned in [`Chart.yaml`](./Chart.yaml) and configured
> entirely through [`values.yaml`](./values.yaml) + the overlays.

## Architecture at a glance

```
   apps ──OTLP :4317/:4318──► OpenTelemetry Collector (gateway, Deployment + HPA)
                                  │ fan-out
              ┌───────────────────┼─────────────────────┐
        logs (OTLP)        metrics (remote_write)     traces (OTLP)
              ▼                    ▼                       ▼
        Loki gateway        Mimir gateway           Tempo distributor
       (SimpleScalable)     (distributed)            (distributed)
        write/read/backend  distributor/ingester/    distributor/ingester/
              │             querier/store-gateway/    querier/compactor +
              │             compactor                 metrics-generator ─┐
              ▼                    ▼                       ▼             │
         object storage      object storage          object storage     │
        (S3/GCS/Azure/MinIO)                                            │
              │                    ▲───── service graphs / span metrics ─┘
              └──────────────┬─────┴───────────────────┐
                             ▼                          ▼
                      Grafana (HA, x3, external Postgres)
                  datasources: Mimir / Loki / Tempo (correlated)
```

Full rationale: [`../docs/SCALING.md`](../docs/SCALING.md).

## Chart / version matrix

| Component | Upstream chart | Pinned version | App version | Repo |
|-----------|----------------|----------------|-------------|------|
| Logs | `grafana/loki` (SimpleScalable) | **6.55.0** | 3.6.7 | grafana |
| Metrics | `grafana/mimir-distributed` | **6.0.6** | 3.0.4 | grafana |
| Traces | `grafana/tempo-distributed` | **1.61.3** | 2.9.0 | grafana |
| UI | `grafana/grafana` | **10.5.15** | 12.3.1 | grafana |
| Ingest | `open-telemetry/opentelemetry-collector` | **0.158.2** | 0.153.0 | otel |

Repos:
- grafana → `https://grafana.github.io/helm-charts`
- otel → `https://open-telemetry.github.io/opentelemetry-helm-charts`

## Files

| File | Purpose |
|------|---------|
| `Chart.yaml` | Umbrella chart; pinned `dependencies:` on the five upstream charts |
| `values.yaml` | Base wiring: service URLs, OTel pipelines, Grafana datasources/dashboards, HA defaults. **No secrets, no storage backend.** |
| `values-s3.yaml` | Object-storage overlay — AWS S3 / S3-compatible (R2, Wasabi, Ceph) |
| `values-gcs.yaml` | Object-storage overlay — Google Cloud Storage |
| `values-azure.yaml` | Object-storage overlay — Azure Blob Storage |
| `values-minio.yaml` | Object-storage overlay — self-hosted in-cluster MinIO (cloud-agnostic / air-gapped) |
| `values-production.yaml` | Production sizing: replicas, retention, resources, zone-aware ingesters, HPA |
| `templates/grafana-dashboards.yaml` | Ships `dashboards/*.json` to Grafana via the sidecar |
| `dashboards/*.json` | Bundled dashboards (Observability Overview) |

Layering model — compose **exactly one** storage overlay, optionally add prod:

```
values.yaml  +  values-<backend>.yaml  [+  values-production.yaml]
```

## Prerequisites

- Kubernetes 1.27+ with a default StorageClass (block PVs for ingesters/compactors).
- `helm` 3.13+ and `kubectl`, both pointed at the target cluster.
- A pre-created object-storage bucket set (one per signal) — see each overlay.
- An external Postgres for Grafana HA (managed RDS/Cloud SQL/etc. or in-cluster).
- Network egress to the two chart repos for `helm dependency build`.

## Install

```bash
# 0. Namespace
kubectl create namespace observability

# 1. Add upstream repos (needed by `helm dependency build`)
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# 2. Resolve pinned dependencies into helm/charts/ (uses Chart.lock if present)
helm dependency build ./helm
#   first time, or to refresh to latest matching the pins:  helm dependency update ./helm

# 3. Create the required Secrets (NEVER inline these in values) — see below.

# 4. Lint + dry-run render
helm lint ./helm -f helm/values.yaml -f helm/values-s3.yaml -f helm/values-production.yaml
helm template obs ./helm -n observability \
  -f helm/values.yaml -f helm/values-s3.yaml -f helm/values-production.yaml | less

# 5. Install (release name MUST be `obs` to match the wired service URLs — see note)
helm upgrade --install obs ./helm -n observability \
  -f helm/values.yaml \
  -f helm/values-s3.yaml \
  -f helm/values-production.yaml \
  --wait --timeout 15m
```

> **Release name.** `values.yaml` wires datasource/collector URLs to stable
> `obs-*` service names via `fullnameOverride`/`nameOverride` keys, so the
> components find each other regardless of release name. Installing as `obs`
> keeps Grafana/Loki/Tempo names identical to those overrides — recommended.
> If you must use another release name, the `obs-*` overrides still pin the
> cross-references, so end-to-end wiring stays correct.

### Required Secrets

Create these **before** install (the chart references them; it never holds
plaintext credentials):

```bash
# Grafana admin
kubectl -n observability create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 24)"

# Grafana external Postgres (HA database)
kubectl -n observability create secret generic grafana-db \
  --from-literal=host=postgres.observability.svc:5432 \
  --from-literal=database=grafana \
  --from-literal=user=grafana \
  --from-literal=password='CHANGE-ME'
```

Object-storage credentials (only if you are **not** using cloud workload
identity — IRSA / GKE Workload Identity / AKS Managed Identity, which is the
recommended path and needs no static keys). See each overlay's comments for the
exact Secret name and key names per component, e.g. for S3 static keys:

```bash
kubectl -n observability create secret generic loki-objstore \
  --from-literal=access_key_id=AKIA... \
  --from-literal=secret_access_key=...
# ...and the mimir-objstore / tempo-objstore equivalents, then uncomment the
# extraEnvFrom lines in values-s3.yaml.
```

For **MinIO**:

```bash
kubectl -n observability create secret generic minio-root \
  --from-literal=rootUser=obsadmin \
  --from-literal=rootPassword="$(openssl rand -base64 24)"
# And the S3-style access secrets the components read (see values-minio.yaml):
kubectl -n observability create secret generic minio-s3 \
  --from-literal=AWS_ACCESS_KEY_ID=obsadmin \
  --from-literal=AWS_SECRET_ACCESS_KEY='<rootPassword>'
kubectl -n observability create secret generic minio-s3-tempo \
  --from-literal=S3_ACCESS_KEY=obsadmin \
  --from-literal=S3_SECRET_KEY='<rootPassword>'
```

## Per-cloud notes

| Backend | Buckets/containers needed | Recommended auth | Overlay |
|---------|---------------------------|------------------|---------|
| **AWS S3** | `*-loki-chunks/ruler/admin`, `*-mimir-blocks/ruler`, `*-tempo-traces` | IRSA (IAM role for service account) | `values-s3.yaml` |
| **GCS** | same set, as GCS buckets | GKE Workload Identity (annotate SAs) | `values-gcs.yaml` |
| **Azure Blob** | same set, as Blob containers | AKS Workload / Managed Identity | `values-azure.yaml` |
| **MinIO** (self-hosted) | created automatically by the bundled MinIO `buckets:` list | root creds Secret + S3 keys | `values-minio.yaml` |

S3-compatible providers (Cloudflare R2, Wasabi, Ceph RGW): use `values-s3.yaml`
and set `endpoint` + `s3ForcePathStyle: true` in the Loki/Mimir/Tempo blocks.

## Send telemetry to it

Point apps at the in-cluster collector (the only endpoint they need to know):

```
OTEL_EXPORTER_OTLP_ENDPOINT=http://obs-opentelemetry-collector.observability.svc.cluster.local:4318
OTEL_RESOURCE_ATTRIBUTES=service.name=<svc>,service.version=<ver>,deployment.environment=prod
```

Expose Grafana / the collector externally via your own Ingress + TLS + auth
(intentionally not shipped here — bring your IngressClass and cert-manager).

## Upgrade / rollback

```bash
# Bump a pinned chart version in Chart.yaml, then:
helm dependency update ./helm
helm upgrade obs ./helm -n observability \
  -f helm/values.yaml -f helm/values-s3.yaml -f helm/values-production.yaml --wait

helm history obs -n observability
helm rollback obs <REVISION> -n observability   # instant rollback to a prior release
```

Stateful components (ingesters, compactors, store-gateways) use StatefulSets;
upgrades roll pods one zone/replica at a time and PDBs guard availability.

## Validation status (this repo)

YAML in every file here is structurally valid (`python -c "yaml.safe_load"`
passes on all of them). `helm lint` / `helm template` / `helm dependency build`
require `helm` + network access to the chart repos and must be run by the
operator in their environment using the commands above. The pinned chart
versions were verified live against both repo `index.yaml` files on 2026-06-21.

## GitOps (optional)

Wire with Argo CD / Flux by pointing an `Application`/`HelmRelease` at this
chart path and your values overlays. The umbrella chart means a single source +
single sync target (no app-of-apps gymnastics).

## See also

- [`../docs/SCALING.md`](../docs/SCALING.md) — scale-out architecture & rationale
- [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) — plane design
- [`../docs/CONSUMERS.md`](../docs/CONSUMERS.md) — integration patterns
