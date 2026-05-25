# consumer-overlay

Use when the observability stack runs **independently** (e.g. one stack per laptop / per cluster, shared by many projects).

## Steps

1. Start the observability stack (once per machine):

   ```bash
   cd ../../
   cp .env.example .env
   # ensure OBS_NETWORK_EXTERNAL=false so compose creates the network
   make up
   ```

2. (Optional) Drop a scrape target file so Prometheus discovers your app:

   ```bash
   cp prometheus-scrape.yml ../../config/prometheus/scrape.d/my-project.yml
   make -C ../../ reload-prometheus
   ```

3. From your project, attach to the network and point apps at `otel-collector`:

   ```bash
   docker compose up -d
   ```

4. Open Grafana → Explore → Loki:

   ```logql
   {service="my-app"} |= "error"
   ```
