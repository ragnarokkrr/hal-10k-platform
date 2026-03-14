# ADR-0007: Observability Stack — Prometheus + Loki + Grafana

**Date**: 2026-03-14
**Status**: Accepted

---

## Context

Phase 5 of the HAL-10k roadmap adds platform observability. Prior to this phase, there
is no metrics collection, no dashboards, and no log aggregation. Container logs evaporate
on restart, and there is no visibility into GPU utilisation, memory pressure, or inference
latency.

Requirements:

- Collect **host-level metrics** (CPU, RAM, disk, network) and **GPU metrics** (ROCm
  utilisation, VRAM, temperature, power)
- Collect **per-container resource metrics** (CPU, memory, network I/O)
- Aggregate **logs** from all running stacks without requiring per-stack changes
- Provide **unified dashboards** covering host, GPU, containers, Traefik, and the AI stack
- Operate on a **single node** with no external storage or network dependencies
- Remain **lightweight** — the machine's RAM is already heavily used by LLM inference

---

## Decision

Deploy the **PLG stack** (Prometheus + Loki + Grafana) with Node Exporter and cAdvisor
as a dedicated `compose/observability/` stack.

| Component | Role |
|-----------|------|
| **Prometheus** | Metrics scrape, storage (30-day TSDB), alerting rules |
| **Loki** | Log aggregation backend (filesystem storage, 30-day retention) |
| **Grafana** | Unified dashboards and log exploration UI |
| **Node Exporter** | Host-level metrics (CPU, RAM, disk, network) |
| **cAdvisor** | Per-container resource metrics |

Log ingestion uses the **Docker Loki log driver** configured globally in
`/etc/docker/daemon.json`. All containers automatically ship logs to Loki without
per-stack changes.

---

## Rationale

### PLG over ELK (Elasticsearch + Logstash + Kibana)

| Criterion | PLG | ELK |
|-----------|-----|-----|
| RAM footprint | Low (Loki ~100 MB, Prometheus ~200 MB) | High (Elasticsearch ≥1 GB JVM heap) |
| Metrics + logs in one UI | Yes (Grafana) | Requires separate stack |
| Prometheus integration | Native (Grafana) | Requires Metricbeat |
| Single-node suitability | High | Medium (Elasticsearch over-engineered) |
| Operational complexity | Low | High |

Elasticsearch is designed for full-text search at scale. On a single node where the
primary goal is visibility, not full-text search, the memory overhead is not justified.

### Docker Loki log driver over Promtail sidecar

The Docker Loki log driver (`grafana/loki-docker-driver`) is installed once as a Docker
plugin and configured globally in `daemon.json`. All containers get log shipping
automatically — no sidecar to deploy per stack, no per-stack volume mounts, no
agent to keep alive.

A Promtail sidecar would require a separate container per stack, bind-mounting each
stack's log paths. For a small number of stacks on a single node, the driver approach
is significantly simpler.

Trade-off: if the Loki container is down, the log driver will buffer and retry, but
`keep-file: true` is set to ensure local JSON log files remain available as fallback.

### cAdvisor over Docker `--experimental` metrics

Docker's built-in metrics endpoint requires experimental features enabled on the daemon
and provides fewer labels and less detail than cAdvisor. cAdvisor is the standard
Prometheus companion for container monitoring and exposes per-container CPU throttling,
per-interface network I/O, and filesystem metrics that the Docker endpoint omits.

### Grafana provisioned dashboards over manual import

Dashboards committed to `compose/observability/grafana/dashboards/` are provisioned by
Grafana on startup from repo-managed JSON. This keeps dashboards version-controlled and
reproducible across deploys. Manual imports are lost on volume teardown.

---

## Consequences

- **Positive**: Full platform visibility from day one for all future phases.
- **Positive**: Log driver approach means zero per-stack changes for log aggregation.
- **Positive**: All observability state (metrics, logs, dashboards) persists across
  container restarts via named Docker volumes.
- **Negative**: Docker daemon restart required to activate the Loki log driver — briefly
  interrupts all running containers. One-time cost.
- **Negative**: cAdvisor requires `privileged: true` and host bind mounts — accepted on
  a single-node lab.
- **Negative**: ROCm GPU metrics require a separate `rocm-smi` exporter container;
  Ollama and LiteLLM metric panels require their respective metrics endpoints to be
  enabled and scraped. All three dashboards show "No data" until resolved. See
  [ADR-0009](ADR-0009-observability-missing-metrics-sources.md) for root causes and
  resolution plan.
- **Negative**: cAdvisor per-container labelling fails with Docker 29+ containerd
  snapshotter. Host-level metrics are unaffected. See
  [ADR-0008](ADR-0008-cadvisor-containerd-snapshotter-limitation.md) for full analysis
  and resolution plan.

---

## Alternatives Considered

| Option | Rejected Because |
|--------|-----------------|
| ELK stack | Elasticsearch RAM overhead (~1+ GB) unacceptable on a memory-constrained inference machine |
| Grafana Agent (unified) | More complex config; PLG components are well-understood and individually replaceable |
| Promtail sidecar | Requires per-stack deployment; Docker log driver is simpler for a small number of stacks |
| Victoria Metrics | Drop-in Prometheus replacement, but no added value at this scale; stick with the reference implementation |
| Netdata | Good for host metrics, weaker for custom application dashboards and log aggregation |
