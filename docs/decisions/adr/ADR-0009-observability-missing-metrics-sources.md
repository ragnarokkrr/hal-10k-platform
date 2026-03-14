# ADR-0009: Observability — Missing Metrics Sources for GPU, Ollama, and LiteLLM Dashboards

**Date**: 2026-03-14
**Status**: Accepted

---

## Context

Phase 5 provisioned six Grafana dashboards. After deployment, four dashboards show
partial or complete "No data". Two root causes were identified:

1. **cAdvisor containerd snapshotter incompatibility** — covered separately in
   [ADR-0008](ADR-0008-cadvisor-containerd-snapshotter-limitation.md).

2. **Missing metrics sources** — the subject of this ADR. Three dashboards query
   Prometheus metrics that no running service currently exposes:
   - **GPU / ROCm** (`hal-gpu-rocm`)
   - **Ollama Inference** (`hal-ollama`)
   - **LiteLLM Proxy** (`hal-litellm`)

---

## Affected Dashboards

### GPU / ROCm (`hal-gpu-rocm`) — all panels

**Metrics queried**:

| Metric | Panel |
|--------|-------|
| `rocm_gpu_utilization_percent` | GPU Utilisation stat + time-series |
| `rocm_memory_used_bytes` | VRAM Used stat + time-series |
| `rocm_memory_total_bytes` | VRAM Usage Over Time time-series |
| `rocm_temperature_celsius` | GPU Temperature stat + Temperature & Power time-series |
| `rocm_power_watts` | GPU Power Draw stat + Temperature & Power time-series |

**Root cause**: No ROCm Prometheus exporter is deployed. None of these metrics are
exposed by any running service. `rocm_gpu_utilization_percent` is a custom metric
namespace — it requires a dedicated exporter that calls `rocm-smi` and translates the
output into Prometheus format.

**Candidate exporters**:

| Project | Image | Notes |
|---------|-------|-------|
| `ntkme/rocm_smi_exporter` | Community | Calls `rocm-smi` via CLI; metric names vary by version |
| `amdgpu_top` Prometheus mode | AMD | `amdgpu_top --prometheus`; requires ROCm userspace |
| Custom script + `pushgateway` | — | Maximum control over metric names; more moving parts |

The dashboard was authored with placeholder metric names (`rocm_*`). The actual metric
names exposed by whichever exporter is chosen will likely differ and will require
dashboard updates.

---

### Ollama Inference (`hal-ollama`) — metric panels

**Metrics queried**:

| Metric | Panel |
|--------|-------|
| `ollama_request_duration_seconds_count` | Requests/s stat + Request Rate by Model |
| `ollama_request_duration_seconds_bucket` | P95 Latency stat + Inference Latency by Model |
| `ollama_tokens_total` | Tokens/s stat |

**Root cause**: Ollama does not expose a Prometheus `/metrics` endpoint by default in
the version deployed (`ollama/ollama:0.6.2-rocm`). The metric names used in the
dashboard (`ollama_request_duration_seconds_*`, `ollama_tokens_total`) are not
standard Ollama metric names and were authored as placeholders.

Ollama added an experimental metrics endpoint in later releases (v0.3.x+), but the
endpoint path and metric names differ from the dashboard assumptions:

- Actual Ollama metrics endpoint: `GET /metrics` (when `OLLAMA_DEBUG=1` or via
  `--prometheus` flag depending on version)
- Actual metric names include `ollama_request_duration_seconds` (histogram) but the
  label structure and counter names require verification against the running version

**Additional note — logs panel**: The Loki panel (`{container_name="ollama"}`) should
work once log ingestion is confirmed. The Docker Loki log driver attaches a
`container_name` label. This panel is not blocked by the missing metrics issue.

---

### LiteLLM Proxy (`hal-litellm`) — metric panels

**Metrics queried**:

| Metric | Panel |
|--------|-------|
| `litellm_request_total` | Total Requests stat + Request Rate by Model + Error Rate |
| `litellm_tokens_total` | Total Tokens stat |
| `litellm_prompt_tokens_total` | Token Throughput by Model |
| `litellm_completion_tokens_total` | Token Throughput by Model |

**Root cause**: LiteLLM does expose a Prometheus-compatible `/metrics` endpoint, but it
is not configured in the current deployment. Two issues:

1. **Endpoint not scraped**: `compose/observability/prometheus.yml` has no scrape job
   for LiteLLM (port 4000 inside the `ai_internal` network, which is not reachable from
   `observability_internal`).

2. **Metric names may differ**: LiteLLM's actual Prometheus metric names (as of
   `main-stable` builds) use:
   - `litellm_requests_total` (not `litellm_request_total`)
   - `litellm_input_tokens_total` (not `litellm_prompt_tokens_total`)
   - `litellm_output_tokens_total` (not `litellm_completion_tokens_total`)

   The dashboard metric names are placeholders that will need updating once the
   endpoint is reachable and actual metric names are confirmed.

3. **Network isolation**: LiteLLM runs on `ai_internal`. Prometheus runs on
   `observability_internal`. For Prometheus to scrape LiteLLM, the LiteLLM container
   must be attached to `observability_internal`, or a separate scrape target must be
   exposed via the `traefik` network.

**Additional note — logs panel**: Same as Ollama — `{container_name="litellm"}` should
work via the Loki driver and is not blocked by the metrics issue.

---

## Decision

Accept all three as **deferred** — they require distinct follow-up work items that are
out of scope for Phase 5:

| Dashboard | Action Required | Phase |
|-----------|----------------|-------|
| GPU / ROCm | Deploy ROCm exporter; update metric names in dashboard | Phase 5 supplement or Phase 6 |
| Ollama Inference | Enable metrics endpoint on Ollama; verify metric names; add scrape job | Phase 5 supplement |
| LiteLLM Proxy | Attach LiteLLM to `observability_internal`; add scrape job; verify metric names | Phase 5 supplement |

Dashboards are provisioned and wired to correct datasources. Once the metrics sources
exist, panels will populate without Grafana changes beyond metric name corrections.

---

## Consequences

- **Positive**: Dashboards are in place; once exporters/endpoints are active, visibility
  is immediate.
- **Negative**: Three dashboards deliver no actionable data in the current state.
- **Negative**: Dashboard metric names were authored as placeholders — some will need
  correction once actual exporter metric names are confirmed against running services.

---

## Resolution Plan

### GPU / ROCm

1. Evaluate available ROCm exporter images against HAL-10k's ROCm 7.2 / RDNA 3.5 iGPU
2. Add exporter service to `compose/observability/docker-compose.yml`
3. Add scrape job to `prometheus.yml`
4. Run `curl http://localhost:<exporter-port>/metrics` and confirm actual metric names
5. Update `grafana/dashboards/gpu-rocm.json` with correct metric names

### Ollama Inference

1. Confirm Ollama metrics endpoint availability:
   ```bash
   docker exec ollama curl -s http://localhost:11434/metrics | head -20
   ```
2. If not available, check whether `OLLAMA_DEBUG=1` or a `--prometheus` flag enables it
   for the deployed version
3. Add scrape job in `prometheus.yml` targeting `ollama:11434`
4. Confirm actual metric names and update `grafana/dashboards/ollama-inference.json`

### LiteLLM Proxy

1. Attach LiteLLM container to `observability_internal` in `compose/ai/docker-compose.yml`
2. Add scrape job in `prometheus.yml` targeting `litellm:4000`
3. Confirm actual metric names:
   ```bash
   curl -sk https://litellm.hal.local/metrics | grep "^# HELP" | head -20
   ```
4. Update `grafana/dashboards/litellm-proxy.json` with correct metric names

---

## Alternatives Considered

| Option | Rejected Because |
|--------|-----------------|
| Remove stub dashboards | Dashboards document intent and remind operators what is pending; removing them loses that signal |
| Use push-based metrics (Pushgateway) | Adds operational complexity; pull-based scrape is consistent with the rest of the stack |
| Defer all to a later phase | GPU and AI inference metrics are directly relevant to Phase 5 goals; resolution should happen in a Phase 5 supplement, not be fully deferred |
