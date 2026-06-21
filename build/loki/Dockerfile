# godx-platform-observability — Loki with baked config.
# Build context = repo root:  docker build -f build/loki/Dockerfile .
ARG BASE_IMAGE=grafana/loki:3.3.0
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source=https://github.com/godx-jp/godx-platform-observability
LABEL org.opencontainers.image.title=godx-observability-loki
LABEL org.opencontainers.image.description="Grafana Loki preconfigured for the godx observability stack"

COPY config/loki/loki-config.yml /etc/loki/loki-config.yml

# Retention is read from the config via env expansion; override LOKI_RETENTION at runtime.
ENV LOKI_RETENTION=720h
CMD ["-config.file=/etc/loki/loki-config.yml", "-config.expand-env=true"]
