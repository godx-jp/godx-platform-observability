# consumer-include

Single-command bring-up: the consumer's `docker-compose.yml` `include`s the observability stack. Best for small monorepos and demos.

## Steps

```bash
cp .env.example .env
docker compose up -d
```

That single command starts:

- Your app(s)
- Loki, Prometheus, Tempo, Grafana, OpenTelemetry Collector, Promtail (from the included stack)

Grafana: <http://localhost:3000>

## Notes

- Requires Docker Compose **v2.20+** for the top-level `include` directive.
- Network `${OBS_NETWORK}` is created locally (because `OBS_NETWORK_EXTERNAL=false`).
- If you want the stack to outlive your app deploys, switch to the `consumer-overlay` pattern instead.
