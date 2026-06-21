# godx-platform-observability — Prometheus with baked scrape config.
# Build context = repo root:  docker build -f build/prometheus/Dockerfile .
ARG BASE_IMAGE=prom/prometheus:v2.55.1
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source=https://github.com/godx-jp/godx-platform-observability
LABEL org.opencontainers.image.title=godx-observability-prometheus
LABEL org.opencontainers.image.description="Prometheus preconfigured for the godx observability stack"

COPY config/prometheus/prometheus.yml /etc/prometheus/prometheus.yml
COPY config/prometheus/scrape.d /etc/prometheus/scrape.d

EXPOSE 9090
# Retention defaults to 30d; override the command in your orchestrator to change it.
CMD ["--config.file=/etc/prometheus/prometheus.yml", \
     "--storage.tsdb.path=/prometheus", \
     "--storage.tsdb.retention.time=30d", \
     "--web.enable-lifecycle", \
     "--web.enable-remote-write-receiver"]
