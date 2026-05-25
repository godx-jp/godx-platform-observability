# Tests

Two layers — both runnable locally and in CI.

| Layer | File | What it does | Containers? |
|-------|------|--------------|-------------|
| **Unit** (static) | `tests/unit.sh` | `docker compose config -q` for every compose file, YAML lint, backend config validation (Loki `-verify-config`, `promtool check`, Tempo load) | one-shot images, no stack |
| **Smoke** (e2e) | `tests/smoke.sh` | Brings the stack up, sends synthetic telemetry via OpenTelemetry `telemetrygen`, verifies Tempo / Prometheus / Grafana ingested it | full stack |

## Run

```bash
make test          # unit + smoke
make test-unit     # static only (fast, no stack)
make test-smoke    # smoke only (assumes stack tearable)

# Or directly:
./tests/unit.sh
./tests/smoke.sh

# Tear down after smoke instead of leaving stack running:
KEEP=0 ./tests/smoke.sh
```

## Requirements

| Tool | Required for | Install |
|------|--------------|---------|
| `docker` + Compose v2.20+ | both layers | https://docs.docker.com/engine/install/ |
| `curl` | smoke | preinstalled |
| `jq` | smoke (optional, used for nicer output) | `brew install jq` / `apt install jq` |
| `yamllint` | unit (optional — skipped if missing) | `pipx install yamllint` |

## CI

`.github/workflows/validate.yml` runs `test-unit` on every PR and `test-smoke` on push to `main`. See workflow for matrix details.

## Adding a test

- **Static check** → add an `assert_cmd "<label>" <cmd>` line in `unit.sh`.
- **Ingestion check** → add a `wait_http` / `assert_contains` in `smoke.sh` after the telemetrygen step.

Helpers live in `tests/lib/assert.sh` (pass / fail / wait_http / assert_http / assert_contains / assert_cmd / summary).

## Conventions

- Pure bash — no `bats`, no Python — keep the dependency footprint matching the rest of the repo.
- Every test prints a line. Final `summary` line reports `N passed, M failed`.
- Exit non-zero on any failure (CI gating).
- Smoke tests must clean up if `KEEP=0`; default keeps the stack running so a developer can poke around afterwards.
