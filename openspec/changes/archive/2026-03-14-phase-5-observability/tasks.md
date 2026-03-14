## 1. Secrets & Configuration

- [x] 1.1 Create `secrets/observability.enc.yaml` with `GF_SECURITY_ADMIN_PASSWORD` placeholder, then encrypt with SOPS
- [x] 1.2 Create `compose/observability/.env.example` with all required variables (image tags, Grafana admin user, Loki retention)

## 2. Loki Log Driver

- [x] 2.1 Install the Docker Loki log driver plugin: `docker plugin install grafana/loki-docker-driver:latest --alias loki --grant-all-permissions`
- [x] 2.2 Configure `/etc/docker/daemon.json` to set `loki` as the default log driver pointing at `http://localhost:3100`
- [x] 2.3 Restart Docker daemon and verify all existing stacks recover: `docker compose -f compose/core/docker-compose.yml ps` and `docker compose -f compose/ai/docker-compose.yml ps`

## 3. Docker Compose Stack

- [x] 3.1 Create `compose/observability/docker-compose.yml` with the `prometheus` service: pinned image, named volume, `observability_internal` network only, healthcheck, `restart: unless-stopped`, bind-mount for `prometheus.yml` config
- [x] 3.2 Add `loki` service: pinned image, named volume, `observability_internal` network only, healthcheck, `restart: unless-stopped`, bind-mount for Loki config
- [x] 3.3 Add `grafana` service: pinned image, named volume, `observability_internal` + `proxy` networks, Traefik labels for `grafana.hal.local`, env vars from `.env`, healthcheck, `restart: unless-stopped`, bind-mounts for provisioning and dashboard JSON files
- [x] 3.4 Add `node-exporter` service: pinned image, read-only host mounts (`/proc`, `/sys`, `/`), `pid: host`, `observability_internal` network only, healthcheck, `restart: unless-stopped`
- [x] 3.5 Add `cadvisor` service: pinned image, read-only bind mounts (`/`, `/var/run`, `/sys`, `/srv/platform/docker`), `observability_internal` network only, healthcheck, `restart: unless-stopped`
- [x] 3.6 Define networks: `observability_internal` (internal bridge) and `proxy` (external, referencing core stack network)
- [x] 3.7 Define named volumes: `prometheus_data`, `grafana_data`, `loki_data`

## 4. Prometheus Configuration

- [x] 4.1 Create `compose/observability/prometheus.yml` with scrape jobs for: Prometheus itself, Node Exporter, cAdvisor, Traefik (`traefik:8082`), and ROCm GPU exporter
- [x] 4.2 Set retention to 30 days (`--storage.tsdb.retention.time=30d`) in Prometheus command args

## 5. Loki Configuration

- [x] 5.1 Create `compose/observability/loki-config.yaml` with filesystem storage, `retention_enabled: true`, `retention_period: 30d`, and ingester/querier config

## 6. Grafana Provisioning

- [x] 6.1 Create `compose/observability/grafana/provisioning/datasources/datasources.yaml` defining Prometheus and Loki datasources
- [x] 6.2 Create `compose/observability/grafana/provisioning/dashboards/dashboards.yaml` pointing at the dashboards directory
- [x] 6.3 Add `compose/observability/grafana/dashboards/host-overview.json` — CPU, RAM, disk, network (based on Node Exporter Full, ID 1860)
- [x] 6.4 Add `compose/observability/grafana/dashboards/gpu-rocm.json` — GPU utilisation, VRAM, temperature, power
- [x] 6.5 Add `compose/observability/grafana/dashboards/container-resources.json` — per-stack CPU/RAM via cAdvisor
- [x] 6.6 Add `compose/observability/grafana/dashboards/traefik.json` — request rate, error rate, latency
- [x] 6.7 Add `compose/observability/grafana/dashboards/ollama-inference.json` — inference request rate and latency
- [x] 6.8 Add `compose/observability/grafana/dashboards/litellm-proxy.json` — token throughput and per-model routing

## 7. Traefik Metrics Integration

- [x] 7.1 Enable Prometheus metrics entrypoint in `compose/core/docker-compose.yml` Traefik command args (`--entrypoints.metrics.address=:8082 --metrics.prometheus.entrypoint=metrics`)
- [x] 7.2 Attach the `core` stack's Traefik container to the `observability_internal` network so Prometheus can scrape it
- [x] 7.3 Redeploy core stack: `docker compose -f compose/core/docker-compose.yml up -d`

## 8. ADR

- [x] 8.1 Create `docs/decisions/adr/ADR-0007-observability-prometheus-loki-grafana.md` documenting the PLG stack choice over ELK and the Loki log driver approach

## 9. Deployment

- [x] 9.1 Add `127.0.0.1 grafana.hal.local` to `/etc/hosts` if not present
- [x] 9.2 Decrypt secrets: `scripts/secrets-decrypt.sh observability` and verify `/srv/platform/secrets/observability.yaml` exists
- [x] 9.3 Bring up the stack: `docker compose -f compose/observability/docker-compose.yml up -d`
- [x] 9.4 Verify all containers healthy: `docker compose -f compose/observability/docker-compose.yml ps`
- [x] 9.5 Verify Prometheus targets: `curl -sk https://grafana.hal.local` returns 200; open Prometheus targets page and confirm all are `UP`
- [x] 9.6 Verify Grafana dashboards: open `https://grafana.hal.local`, log in, confirm all six dashboards are present and showing data

## 10. Runbooks & Documentation

- [x] 10.1 Create `docs/runbooks/observability.md` — bring-up, teardown, adding scrape targets, Loki log driver reinstall steps
- [x] 10.2 Update `docs/services-catalog.md` with Prometheus, Loki, Grafana, Node Exporter, cAdvisor entries
- [x] 10.3 Update `docs/ports.md` with internal ports: Prometheus (9090), Loki (3100), Grafana (3000 internal), Node Exporter (9100), cAdvisor (8080), Traefik metrics (8082)
- [x] 10.4 Create `docs/testcases/observability-stack-test.md` with manual test cases covering all spec scenarios

## 11. ROADMAP Update

- [x] 11.1 Mark all Phase 5 checklist items as complete in `ROADMAP.md`
