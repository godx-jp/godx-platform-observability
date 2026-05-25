# Examples

How a downstream project (microservice monorepo, single app, infra repo) wires itself into this observability plane.

| Pattern | Path | When |
|---------|------|------|
| **Compose include** | [consumer-include/](./consumer-include/) | Monorepo with own `docker-compose.yml` — pulls observability stack in as a sibling. |
| **External network + scrape overlay** | [consumer-overlay/](./consumer-overlay/) | Observability stack already running; app project just attaches and registers scrape targets. |

Both patterns assume this repo is checked out as a sibling directory:

```
<workspace>/
├── godx-platform-observability/    ← this repo
└── my-project/                     ← consumer
```

Adjust paths if you place this repo elsewhere (e.g. `vendor/observability/` via submodule).
