## Context

HAL-10k currently has no telemetry. Traefik, Ollama, LiteLLM, and Open WebUI produce logs that evaporate on container restart, and there are no metrics dashboards to detect GPU thermal events, memory pressure, or inference degradation. Phase 5 adds the PLG+Prometheus stack (Prometheus, Loki, Grafana) as a stable, always-on observability tier so every downstream phase can plug in from day one.

## Goals / Non-Goals

**Goals:**
- Deploy Prometheus, Grafana, Loki, Node Exporter, and cAdvisor as a single `compose/observability/` stack
- Collect host metrics (CPU, RAM, disk, network) and GPU metrics (ROCm utilisation, VRAM, temperature)
- Collect per-container resource metrics via cAdvisor
- Aggregate logs from all running stacks via Docker Loki log driver
- Provision foundation Grafana dashboards for host, GPU, containers, Traefik, and AI stack
- Expose Grafana via Traefik HTTPS at `grafana.hal.local`
- Persist Grafana state and Prometheus data via named volumes

**Non-Goals:**
- Distributed tracing (no Jaeger/Tempo — single node, not warranted yet)
- Long-term metrics storage beyond local retention (no Thanos/Cortex)
- PagerDuty or external alerting channels (Alertmanager email/webhook config deferred)
- Automatic dashboard import from Grafana.com (dashboards provisioned from repo files)

## Decisions

**1. PLG stack (Prometheus + Loki + Grafana) over alternatives**

ELK (Elasticsearch + Logstash + Kibana) is memory-heavy and operationally complex for a single node. The PLG stack integrates natively with Grafana, Loki is lightweight, and Prometheus is the standard for container metrics. Grafana unifies metrics and logs in one UI.

**2. Docker Loki log driver for log ingestion over Promtail sidecar**

The Docker Loki log driver (`grafana/loki-docker-driver`) ships logs directly from the Docker daemon without requiring a sidecar per stack. Simpler to configure; the driver is set globally in Docker daemon config (`/etc/docker/daemon.json`) with a per-stack override to point at `loki:3100`. Promtail is not deployed.

**3. cAdvisor for container metrics over Prometheus Docker SD**

cAdvisor provides richer per-container resource metrics (CPU throttling, network I/O per container) than Docker's built-in `/metrics` endpoint. It's a single container with read-only host mounts and is the standard Prometheus companion for container monitoring.

**4. ROCm GPU metrics via `rocm-smi` exporter sidecar**

`dcgm-exporter` is NVIDIA-only. For AMD ROCm, a lightweight `rocm-smi` exporter container queries `rocm-smi --showallinfo --json` and exposes Prometheus metrics. Image: `ghcr.io/wkennedy/rocm-smi-exporter` (or build a minimal exporter script). Exposes GPU utilisation, VRAM used/total, temperature, and power draw.

**5. Grafana dashboard provisioning via repo-managed JSON files**

Dashboards committed to `compose/observability/dashboards/` are auto-provisioned by Grafana's provisioning mechanism on startup. This keeps dashboards version-controlled and reproducible, avoiding manual import on each deploy.

**6. Observability stack on `observability` internal network + `proxy` network**

Prometheus, Loki, and cAdvisor are internal only. Grafana joins both `observability_internal` and `proxy` (for Traefik routing). No observability port is exposed to the host.

## Risks / Trade-offs

- **Loki log driver global config requires Docker daemon restart** → Schedule during a planned maintenance window; all containers restart.
- **rocm-smi exporter image maturity** → May need a custom minimal exporter; document fallback to polling `rocm-smi` manually.
- **cAdvisor requires privileged host mounts** → Necessary for accurate metrics; accepted risk on single-node lab.
- **Grafana provisioned dashboards overwrite manual edits** → Document that dashboard edits must be committed to repo to persist.
- **Prometheus scrape interval vs. Ollama load** → Keep default 15s; Ollama metrics endpoint is lightweight.

## Migration Plan

1. Deploy observability stack (`docker compose up -d`)
2. Restart Docker daemon to activate Loki log driver (all containers restart)
3. Verify Prometheus targets are all `UP`
4. Verify Loki receiving logs from core and ai stacks
5. Open Grafana dashboards and confirm data flowing

**Rollback**: Remove Loki log driver from `/etc/docker/daemon.json`, restart daemon, take down observability stack. No data loss to other stacks.

## Open Questions

- Which `rocm-smi` exporter image to pin — evaluate `wkennedy/rocm-smi-exporter` vs. a custom script at deploy time.
- Alertmanager: deploy but leave notification channels unconfigured until Phase 9 (or later).
