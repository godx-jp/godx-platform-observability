# godx-platform-observability — OpenTelemetry Collector with baked pipeline config.
# Build context = repo root:  docker build -f build/otel-collector/Dockerfile .
ARG BASE_IMAGE=otel/opentelemetry-collector-contrib:0.115.1
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source=https://github.com/godx-jp/godx-platform-observability
LABEL org.opencontainers.image.title=godx-observability-otel-collector
LABEL org.opencontainers.image.description="OTLP ingress gateway with godx observability pipeline baked in"

COPY config/otel-collector/config.yaml /etc/otelcol/config.yaml

# OTLP gRPC / HTTP
EXPOSE 4317 4318
CMD ["--config=/etc/otelcol/config.yaml"]
