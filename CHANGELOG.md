# Changelog

All notable changes to this project will be documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) · versioning: [SemVer](https://semver.org/).

## [Unreleased]

## [0.1.0] — 2026-05-25

### Added
- Initial scaffold.
- Multi-container compose: Loki, Promtail, Prometheus, Tempo, Grafana, OpenTelemetry Collector gateway.
- All-in-one compose using upstream `grafana/otel-lgtm` (dev/CI flavour).
- Grafana datasource provisioning with logs ↔ traces ↔ metrics correlation.
- Prometheus file-based service discovery for consumer scrape targets.
- Example consumer-include and consumer-overlay snippets.
- Helm values placeholder for production Kubernetes deployments.
