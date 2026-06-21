# godx-platform-observability — Grafana with baked datasources + dashboards.
# Build context = repo root:  docker build -f build/grafana/Dockerfile .
ARG BASE_IMAGE=grafana/grafana:11.4.0
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source=https://github.com/godx-jp/godx-platform-observability
LABEL org.opencontainers.image.title=godx-observability-grafana
LABEL org.opencontainers.image.description="Grafana with godx LGTM datasources and dashboards provisioned in"

COPY config/grafana/provisioning /etc/grafana/provisioning
COPY dashboards /var/lib/grafana/dashboards

# Sensible defaults; override admin creds and root URL at runtime.
ENV GF_FEATURE_TOGGLES_ENABLE=traceqlEditor

EXPOSE 3000
