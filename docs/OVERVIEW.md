# Product overview

What this platform does, how data flows through it end-to-end, and which screens you (or your consumers) actually interact with.

> If you're integrating: jump to [CONSUMERS.md](./CONSUMERS.md).
> If you're shipping app code: read [CONTRACT.md](./CONTRACT.md).
> This document explains the **product** — for stakeholders, new platform engineers, and onboarding sessions.

---

## 1. What it does — six responsibility groups

| Group | Responsibility | Component |
|-------|----------------|-----------|
| **Ingest** | Accept telemetry from any app through **a single OTLP endpoint** (gRPC `:4317` / HTTP `:4318`) | OpenTelemetry Collector |
| **Enrich** | Add `deployment.environment`, `cluster`, tenant ID; redact PII; apply sampling | OpenTelemetry Collector (processors) |
| **Store** | Persist **logs**, **metrics**, **traces** in backends purpose-built per signal | Loki · Prometheus · Tempo |
| **Correlate** | Wire logs ↔ traces ↔ metrics together via `trace_id` and `service.name` | Grafana datasource provisioning |
| **Visualize** | Dashboards, ad-hoc query, service maps, flame graphs | Grafana |
| **Alert** | Rule engine + notification channels (email, Slack, webhook, PagerDuty…) | Grafana Alerting (+ Prometheus rules) |

What it explicitly does **not** do:

- Hold any business data.
- Run any application code.
- Replace application APM agents inside a single language ecosystem — it _aggregates_ what those agents emit.
- Replace a SIEM. (Security analytics live elsewhere; this is operational observability.)

---

## 2. End-to-end flow

```
                                ┌────────────────────────────────────────┐
                                │           ANY consumer project          │
                                │                                        │
┌─────────────┐                 │  ┌─────────┐  ┌─────────┐  ┌────────┐  │
│   User      │                 │  │ app-A   │  │ app-B   │  │ worker │  │
│ (dev / SRE) │                 │  └────┬────┘  └────┬────┘  └────┬───┘  │
└──────┬──────┘                 │       │ JSON log   │            │      │
       │                        │       │ OTLP       │            │      │
       │ HTTPS                  │       └────────────┴────────────┘      │
       ▼                        │                    │                   │
┌─────────────┐                 └────────────────────┼───────────────────┘
│   Grafana   │ ◄── query ─┐                         │ :4317 / :4318
│   (UI)      │            │                         ▼
└──────┬──────┘            │            ┌──────────────────────────┐
       │ alert             │            │  OpenTelemetry Collector │
       ▼                   │            │  ┌──────────────────┐    │
┌─────────────┐            │            │  │ receivers: otlp  │    │
│ Email/Slack │            │            │  │ processors:      │    │
│ Webhook     │            │            │  │   memory_limiter │    │
│ PagerDuty   │            │            │  │   resource       │    │
└─────────────┘            │            │  │   batch          │    │
                           │            │  │ exporters:       │    │
                           │            │  └──────────────────┘    │
                           │            └──┬────────┬────────┬─────┘
                           │     logs      │ metrics│ traces │
                           │               ▼        ▼        ▼
                           │           ┌──────┐ ┌──────┐ ┌──────┐
                           └───────────┤ Loki │ │ Prom │ │ Tempo│
                                       └──┬───┘ └──┬───┘ └──┬───┘
                                          │        ▲        │
                              Promtail ───┘        │        │
                                (Docker      Tempo metrics  │
                                socket;      generator      │
                                opt-in via   (span → metrics) ─► remote_write
                                label)
```

Three properties of this topology to keep in mind:

1. **One ingress, many backends.** Apps only know about the Collector. Swapping Loki ↔ another logs backend never touches app code.
2. **Each signal goes to its specialist.** Loki is label-based and cheap for logs; Tempo stores traces; Prometheus stores time-series. No "one DB rules them all".
3. **Correlation happens at query time.** Grafana stitches the three together using shared identifiers (`trace_id`, `service.name`). The storage layers stay decoupled.

---

## 3. Sub-flows

### 3.1 A single request, end-to-end

```
1. Client calls app-A (`POST /api/orders`)
2. OTel SDK in app-A creates trace_id + root span
3. app-A → app-B (gRPC) — W3C `traceparent` header propagates context
4. app-B records a child span `POST /api/payment` and logs JSON
     {"ts":"...", "level":"info", "trace_id":"...", "msg":"charged"}
5. Both apps push spans over OTLP → Collector
6. Collector:
     - injects deployment.environment / tenant
     - batches every 5s
     - fans out:
         traces  → Tempo  (gRPC :4317)
         logs    → Loki   (OTLP HTTP /otlp)
         metrics → Prom   (remote_write)
7. User opens Grafana → Explore → Tempo → searches the trace ID
8. Trace view shows a waterfall: app-A → app-B span
9. "View related logs" auto-runs `{trace_id="..."}` in Loki
10. "View service graph" highlights edge app-A → app-B with latency
```

### 3.2 Alert lifecycle

```
Grafana Alert Rule
  rate(http_server_requests_total{status=~"5.."}[5m]) > 0.05
       │ FIRING
       ▼
Alertmanager (grouping + dedupe + inhibition)
       │
       ├─► Email channel       (low priority)
       ├─► Slack #ops          (working hours)
       ├─► Webhook PagerDuty   (on-call rotation)
       └─► (silenced? ─► drop)
```

### 3.3 Onboarding a new service

```
Consumer-side                                Plane-side
─────────────                                ──────────
1. Add OTEL_EXPORTER_OTLP_ENDPOINT to env    (no change)
2. Set service.name / service.version
3. Run JSON logger to stdout                 (Promtail picks up via Docker label)
4. Expose /metrics
5. Drop config/prometheus/scrape.d/<svc>.yml ◄── consumer pushes scrape target
6. make reload-prometheus                    ◄── hot reload, no restart
7. Verify in Prometheus → Targets            (UP / DOWN status)
8. Build a dashboard, save under folder
```

---

## 4. UI surfaces — what screens exist

≈90% of human interaction happens in **Grafana**. Loki and Tempo have no UI of their own (API only — Grafana is the front-end). Prometheus ships a small built-in UI for debugging.

### 4.1 Grafana (primary UI — `http://localhost:3000`)

| # | Screen | Path | Purpose | Typical user |
|---|--------|------|---------|--------------|
| 1 | **Home** | `/` | Landing — pinned dashboards, news, starters | Everyone |
| 2 | **Explore — Logs** | `/explore` + datasource Loki | LogQL ad-hoc: `{service="app-A"} \|= "error"` | Dev, SRE |
| 3 | **Explore — Metrics** | `/explore` + datasource Prometheus | PromQL: `rate(http_server_requests_total[5m])` | SRE, platform |
| 4 | **Explore — Traces** | `/explore` + datasource Tempo | TraceQL: `{ resource.service.name="app-A" && duration > 500ms }` | Dev (perf) |
| 5 | **Trace view (waterfall)** | from Explore → click a trace | Span tree, attributes, events, jump links to Logs/Metrics | Dev |
| 6 | **Service Graph** | Tempo datasource → Service Graph tab | Topology auto-generated from spans (nodes = services, edges = calls) | Architect, SRE |
| 7 | **Dashboards — Browse** | `/dashboards` | List by folder (Observability/, Apps/, …) | Everyone |
| 8 | **Dashboard view** | `/d/{uid}` | Panel grid with time picker, variables, refresh | PM, SRE, dev |
| 9 | **Dashboard edit** | `/d/{uid}?editPanel=1` | Panel CRUD: query + visualization (graph, table, heatmap, log…) | Dev, SRE |
| 10 | **New dashboard** | `/dashboard/new` | Blank canvas → add panels | Dev |
| 11 | **Alerting — Alert rules** | `/alerting/list` | List of rules (firing / pending / normal); folder & evaluation group | SRE |
| 12 | **Alerting — Rule editor** | `/alerting/new` | Query + condition + folder + labels; preview before saving | SRE, dev |
| 13 | **Alerting — Contact points** | `/alerting/notifications` | Email / Slack / Webhook / PagerDuty / OnCall integrations | SRE, platform |
| 14 | **Alerting — Notification policy** | `/alerting/routes` | Route by label → contact point; `group_wait`, `repeat_interval` | SRE |
| 15 | **Alerting — Silences** | `/alerting/silences` | Temporary mute (maintenance windows) | SRE on-call |
| 16 | **Alerting — History** | `/alerting/history` | Fire/resolve timeline | Post-incident review |
| 17 | **Connections — Data sources** | `/connections/datasources` | Provisioned: `Prometheus` (default), `Loki`, `Tempo` | Platform admin |
| 18 | **Administration — Users** | `/admin/users` | Accounts, role (Viewer/Editor/Admin) | Admin |
| 19 | **Administration — Teams** | `/org/teams` | Groups + folder permissions | Admin |
| 20 | **Administration — Organizations** | `/admin/orgs` | Multi-tenant (one org per consumer project) | Admin |
| 21 | **API keys / Service accounts** | `/org/serviceaccounts` | Tokens for CI / Terraform / Grafonnet sync | Platform |
| 22 | **Plugins** | `/plugins` | Install extra panels / datasources (keep minimal) | Admin |
| 23 | **Preferences (per-user)** | `/profile/preferences` | Theme (dark/light), home dashboard, timezone | All users |

### 4.2 Prometheus (debug UI — `http://localhost:9090`)

| # | Screen | Path | Purpose |
|---|--------|------|---------|
| 24 | **Graph** | `/graph` | PromQL ad-hoc (Grafana Explore is better — but useful for quick sanity checks) |
| 25 | **Alerts** | `/alerts` | State of Prometheus-native rules (only if you ship `rule_files`) |
| 26 | **Targets** | `/targets` | Scrape job status — **critical** when onboarding new services |
| 27 | **Service discovery** | `/service-discovery` | What `file_sd` resolves from `scrape.d/*.yml` |
| 28 | **Configuration** | `/config` | Dump live config (after reload) |
| 29 | **Rules** | `/rules` | Recording + alerting rules |
| 30 | **TSDB status** | `/tsdb-status` | Top label cardinality — debug high-cardinality OOM |

### 4.3 OpenTelemetry Collector (endpoints, no UI)

| # | Endpoint | Purpose |
|---|----------|---------|
| 31 | `:13133/` | Health check (liveness/readiness) |
| 32 | `:8888/metrics` | Self-metrics (queue size, dropped spans, batch latency) — scraped by Prometheus |

### 4.4 Loki & Tempo (no own UI)

All access is via Grafana Explore. Power users may install CLIs (`logcli`, `tempo-cli`); both are out-of-scope tools, not part of the product surface.

---

## 5. User-journey map

| Journey | Screen sequence (numbers map to §4) |
|---------|-------------------------------------|
| **Dev debugs a prod bug** | Home (1) → Explore Logs (2) → find error → click `trace_id` → Trace view (5) → click slow DB span → "View related logs" → Explore Logs auto-filtered (2) |
| **SRE on-call (alert fires)** | Email/Slack → link to Alert rule (11) → "View dashboard" (8) → Explore Metrics drill-down (3) → Explore Traces (4) → Trace view (5) |
| **PM checks KPI** | Bookmark Dashboard view (8) — RED panel, conversion; no need to know LogQL/PromQL |
| **Architect reviews topology** | Service Graph (6) → click a slow edge → Trace view (5) |
| **Onboarding new service** | Edit `config/prometheus/scrape.d/<svc>.yml` → `make reload-prometheus` → Prometheus Targets (26) verify UP → Grafana Explore Metrics (3) sanity-check query |
| **Tuning alerts** | Rule editor (12) preview → Notification policy (14) → Silences (15) for maintenance |
| **Platform admin onboards a team** | Users (18) → Teams (19) → set folder permissions on dashboards (7) |

---

## 6. What's intentionally out of scope

| Out of scope | Why |
|--------------|-----|
| Business dashboards (revenue, conversion funnels) | Belongs in the BI / data warehouse stack, not on operational telemetry |
| Long-term archive (years) | Use object-store retention or a data lake; the plane keeps weeks–months |
| SIEM / security analytics | Different access model, different retention, different compliance requirements |
| Per-language APM | OTel SDKs already do that; this plane _aggregates_ what they emit |
| A custom UI | Grafana covers it; building another UI is rebuilding Grafana |

---

## 7. Putting it in one sentence

> One OTLP endpoint in, three specialized stores, one Grafana out — a vendor-neutral observability product that any project can drop in and use without writing a single line of platform code.
