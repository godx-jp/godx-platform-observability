# godx-platform-observability — Promtail with baked config.
# Build context = repo root:  docker build -f build/promtail/Dockerfile .
#
# Note: shipping Docker logs still requires mounting /var/run/docker.sock at runtime.
ARG BASE_IMAGE=grafana/promtail:3.3.0
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source=https://github.com/godx-jp/godx-platform-observability
LABEL org.opencontainers.image.title=godx-observability-promtail
LABEL org.opencontainers.image.description="Promtail preconfigured to ship Docker container logs to godx Loki"

COPY config/promtail/promtail-config.yml /etc/promtail/promtail-config.yml

CMD ["-config.file=/etc/promtail/promtail-config.yml"]
