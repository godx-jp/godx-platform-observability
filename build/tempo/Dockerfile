# godx-platform-observability — Tempo with baked config.
# Build context = repo root:  docker build -f build/tempo/Dockerfile .
ARG BASE_IMAGE=grafana/tempo:2.6.1
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source=https://github.com/godx-jp/godx-platform-observability
LABEL org.opencontainers.image.title=godx-observability-tempo
LABEL org.opencontainers.image.description="Grafana Tempo preconfigured for the godx observability stack"

COPY config/tempo/tempo.yml /etc/tempo.yml

CMD ["-config.file=/etc/tempo.yml", "-target=all"]
