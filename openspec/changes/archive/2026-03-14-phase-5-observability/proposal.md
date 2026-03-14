## Why

The platform has no metrics, dashboards, or log aggregation. There is currently no visibility into GPU utilisation, container resource consumption, Traefik request rates, or Ollama inference latency. Phase 5 adds a full observability stack so every subsequent phase can wire metrics and alerts from day one.

## What Changes

- Deploy Prometheus + Grafana + Loki as a dedicated `compose/observability/` stack
- Add Node Exporter for host-level CPU, RAM, disk, and network metrics
- Add cAdvisor for per-container resource metrics
- Configure Loki log driver for all existing stacks (core, ai)
- Provision a foundation set of Grafana dashboards (host, GPU/ROCm, containers, Traefik)
- Provision AI-stack dashboards (Ollama inference, LiteLLM throughput, Open WebUI sessions)
- Add SOPS-encrypted secrets for Grafana admin credentials
- Expose Grafana and Alertmanager via Traefik HTTPS routing

## Capabilities

### New Capabilities

- `prometheus-metrics`: Prometheus scrape targets, retention config, and alerting rules for host and container metrics
- `grafana-dashboards`: Grafana provisioned dashboards and datasources for host, GPU, containers, Traefik, and AI stack
- `loki-log-aggregation`: Loki log ingestion, Promtail/Docker log driver config, and log retention policy
- `node-exporter`: Node Exporter host metrics (CPU, RAM, disk I/O, network)
- `cadvisor-metrics`: cAdvisor per-container resource metrics

### Modified Capabilities

- `traefik-core-proxy`: Add Traefik metrics endpoint (`/metrics`) to enable Prometheus scraping

## Impact

- New stack: `compose/observability/docker-compose.yml`
- New secrets: `secrets/observability.enc.yaml` (Grafana admin password)
- New hostnames: `grafana.hal.local`, `alertmanager.hal.local` (via Traefik)
- Existing stacks (core, ai) updated with Loki log driver and Prometheus scrape annotations
- `docs/ports.md` updated with Prometheus (9090), Grafana (3000), Loki (3100), cAdvisor (8080), Node Exporter (9100)
- `docs/services-catalog.md` updated with all observability services
