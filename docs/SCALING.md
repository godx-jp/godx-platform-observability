# Scaling — production (Kubernetes) architecture & rationale

The `compose/` stacks run a **single node** of each backend: monolithic Loki and
Tempo, one Prometheus, Grafana on embedded SQLite. That is correct for dev and
moderate single-host load, but it has hard ceilings: a single process for
ingest/query, local-disk storage that cannot be shared or scaled, and a UI that
cannot run more than one replica.

Production replaces each single node with its **horizontally scalable upstream
deployment**, all reading/writing **object storage** so compute scales
independently of data. This is delivered as a Helm umbrella chart of pinned
upstream charts — see [`../helm/`](../helm/). No forks: pure values overlays.

## What changes vs. the compose stack

| Signal | Dev (compose) | Production (Helm) | Why |
|--------|---------------|-------------------|-----|
| Logs | Loki monolith, filesystem | **Loki SimpleScalable** (read/write/backend) on object storage | Separate the write path (ingest) from the read path (query) so each scales on its own; durable, shared, cheap storage. |
| Metrics | single Prometheus, local TSDB | **Mimir distributed** on object storage | A single Prometheus is a scaling and HA dead-end (one process, local disk, no native long-term store, no replication). |
| Traces | Tempo monolith, local | **Tempo distributed** on object storage | Independent distributor/ingester/querier/compactor; object-store blocks. |
| UI | Grafana + SQLite, 1 replica | **Grafana x3 + external Postgres** | SQLite can't be shared across replicas; Postgres makes Grafana stateless-per-pod and HA. |
| Ingest | OTel Collector, 1 container | **OTel Collector gateway, Deployment + HPA** | Autoscale the single ingest choke point with load. |

## Why Mimir instead of a single Prometheus

A single Prometheus stores series in a local TSDB on one node. That gives you:

- **No horizontal scale** — one process ingests and queries everything; vertical
  scaling hits a wall (millions of active series, high cardinality).
- **No HA** — node loss = gap in metrics; running two Prometheis double-scrapes
  and still doesn't share data or deduplicate queries cleanly.
- **No native long-term storage** — retention is bounded by local disk.

**Grafana Mimir** is the same Prometheus engine re-architected for scale:

- **Microservices** — distributor, ingester, querier, query-frontend,
  query-scheduler, store-gateway, compactor scale independently.
- **Replication factor 3** across ingesters (zone-aware in prod) — no data loss
  on node/AZ failure.
- **Object storage** for blocks — effectively unlimited, cheap retention
  (90d in the prod overlay), compaction handled by the compactor.
- **Prometheus-compatible** — apps and the OTel Collector `remote_write` into
  Mimir's gateway exactly as they would to Prometheus; Grafana queries it with
  the `prometheus` datasource type (we keep the datasource UID `prometheus` so
  existing dashboards/panels port over unchanged).

The dev stack keeps Prometheus precisely because it's simpler for one host; prod
needs scale and HA, so Mimir.

## How signals flow in the distributed topology

1. **Apps** export OTLP (gRPC :4317 / HTTP :4318) to the **one** endpoint they
   know: the **OpenTelemetry Collector gateway** (Deployment, HPA 3→20).
2. The collector fans out (mirrors `config/otel-collector/config.yaml`):
   - **Logs** → `otlphttp` to the **Loki gateway** `/otlp` (native OTLP push).
   - **Metrics** → `prometheusremotewrite` to the **Mimir gateway** `/api/v1/push`.
   - **Traces** → `otlp` to the **Tempo distributor** :4317.
3. **Tempo's metrics-generator** computes **service graphs + span metrics** and
   `remote_write`s them into **Mimir** (same as the dev `tempo.yml`), so RED
   metrics for traces appear alongside app metrics.
4. **Grafana** (x3) queries the three gateways via provisioned datasources, with
   the dev correlations preserved: Loki `derivedFields` → Tempo TraceID,
   Tempo `tracesToLogs`/`tracesToMetrics`/`serviceMap`/`nodeGraph`.

Apps can also `remote_write` Prometheus metrics directly into the Mimir gateway,
or push OTLP for any signal — the collector is the recommended single ingress.

## HA, security, retention

- **Replicas + RF=3** on every stateful tier (Loki write/backend, Mimir/Tempo
  ingesters), **PodDisruptionBudgets** so rollouts/drains never take a quorum
  down, **pod anti-affinity** + zone-aware ingesters (prod) to survive AZ loss.
- **Autoscaling** — HPA on the OTel gateway and Loki read path; Mimir/Tempo
  scale by replica count (and optional KEDA, left off by default).
- **Resource requests/limits** on every component for schedulability and
  predictable QoS.
- **Object storage** is cloud-agnostic: S3 / GCS / Azure Blob / self-hosted
  MinIO via swappable overlays — compute and storage scale independently.
- **Security** — components run as non-root (chart defaults); **all credentials
  come from Kubernetes Secrets** referenced by the values (object-storage keys,
  Grafana admin, Grafana Postgres). Cloud workload identity (IRSA / GKE WI / AKS
  MI) is the recommended path and needs no static keys at all. Nothing sensitive
  is inlined in values files.
- **Retention** (prod overlay): logs 30d (Loki compactor), metrics 90d (Mimir
  compactor), traces 14d (Tempo compactor). Tune in `values-production.yaml`.

## Durability ladder — what happens to logs under overload

This is a telemetry pipeline, not a durable queue. Under sustained overload a
naive setup **drops logs silently** — mostly at the Loki rate-limit boundary
(HTTP 429) and the collector's `memory_limiter`, and on any collector/ingester
restart. The stack hardens loss in graded steps; pick the rung your SLO needs.

| Rung | Mechanism | Protects against | Where configured |
|------|-----------|------------------|------------------|
| 0 | App SDK exports **async + bounded queue + drop-on-full** | The app **never blocks** — it sheds visibility, not availability | App OTel SDK (do **not** set blocking/unbounded export) |
| 1 | Collector **`retry_on_failure`** (backoff) | Backend 429 / 5xx spikes — retries instead of dropping | `otelCollector.config.exporters.*` (enabled) |
| 2 | Collector **`sending_queue`** (in-memory spool) | Short bursts while a backend catches up | `otelCollector.config.exporters.*` (enabled) |
| 3 | Generous, autoscaled **Loki ingestion limits** + read/write HPA | The 429 boundary itself — raise `ingestion_rate_mb`/`burst` (prod: 64/128) and scale writers | `loki.loki.limits_config`, `loki.write.replicas` |
| 4 | **Loki WAL + `replication_factor: 3`** | An ingester dying with un-flushed chunks | `loki.commonConfig.replication_factor` (prod overlay) |
| 5 | Collector **persistent queue** (`file_storage` ext on a PVC) | Loss across a **collector restart** — needs a StatefulSet/agent tier with node-local disk | add `file_storage` extension + volume |
| 6 | **Kafka buffer** in front of Loki/Tempo (native Kafka ingestion) | Multi-minute backend outages, >1 TB/day spikes — durable spool that decouples producers | external Kafka + Loki/Tempo Kafka target |

Rungs 0–4 are wired in this chart. Rungs 5–6 are deployment choices you add when
your loss budget approaches zero. **Golden rule:** export must stay async +
bounded + drop-on-overflow so overload costs *visibility, never the app*.

> Logs you are legally/financially forbidden to lose (audit, billing) do **not**
> belong in a best-effort telemetry pipeline — write them to a durable store
> (DB/Kafka) and treat Loki/Grafana as observability, where sampling/loss is
> acceptable.

## Sizing

The `values-production.yaml` overlay is a realistic baseline (≈ hundreds of
GB/day logs, millions of active series). Capacity-plan against the upstream
guides before going live:

- Loki — https://grafana.com/docs/loki/latest/setup/size/
- Mimir — https://grafana.com/docs/mimir/latest/manage/run-production-environment/planning-capacity/
- Tempo — https://grafana.com/docs/tempo/latest/operations/deployment/

Beyond ~1 TB/day of logs, switch Loki from `SimpleScalable` to
`deploymentMode: Distributed` (same chart, more granular targets).

## Install

See [`../helm/README.md`](../helm/README.md) for copy-pasteable commands
(`helm repo add` → `helm dependency build` → secrets → `helm upgrade --install`),
per-cloud notes, and upgrade/rollback.
