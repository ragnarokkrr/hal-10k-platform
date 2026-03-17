# TECH_DEBT.md — HAL-10k Platform

Known limitations, deferred fixes, and backlog items that are accepted as current state
but should be resolved in future maintenance windows or phases.

Each item links to the ADR or ROADMAP entry where the decision to defer was recorded.

---

## Observability Gaps

### OBS-1 — cAdvisor: No Per-Container Metrics (Docker Containerd Snapshotter)

**What:** cAdvisor cannot discover Docker containers when Docker uses the containerd
snapshotter (`io.containerd.snapshotter.v1`, the default in Docker 29+). The Container
Resources Grafana dashboard shows no data.

**Impact:** No per-container CPU, memory, or network metrics. Host-level metrics (Node
Exporter) and Traefik metrics are fully operational. Per-container alerting cannot be
configured until fixed.

**Fix:** Switch Docker storage driver to `overlay2` in `/etc/docker/daemon.json`. Requires
stopping all stacks, pruning all images (~5 GB), and re-pulling (~30–60 min downtime).
The full procedure is documented in ADR-0008.

**Trigger:** Schedule a maintenance window.

**Ref:** [ADR-0008](docs/decisions/adr/ADR-0008-cadvisor-containerd-snapshotter-limitation.md)

---

### OBS-2 — GPU / ROCm Dashboard: No Metrics Source

**What:** The `hal-gpu-rocm` Grafana dashboard queries `rocm_gpu_utilization_percent`,
`rocm_memory_used_bytes`, `rocm_temperature_celsius`, and `rocm_power_watts` — none of
which are exposed by any running service. No ROCm Prometheus exporter is deployed.

**Impact:** GPU utilisation, VRAM usage, temperature, and power draw are not visible in
Grafana. Operators must use `rocm-smi` manually.

**Fix:** Evaluate and deploy a ROCm exporter (`ntkme/rocm_smi_exporter` or
`amdgpu_top --prometheus`). Add scrape job to `prometheus.yml`. Update dashboard metric
names once actual names are confirmed from the running exporter.

**Trigger:** Phase 5 supplement or Phase 8 prep.

**Ref:** [ADR-0009](docs/decisions/adr/ADR-0009-observability-missing-metrics-sources.md)

---

### OBS-3 — Ollama Inference Dashboard: Metrics Endpoint Not Configured

**What:** The `hal-ollama` dashboard queries `ollama_request_duration_seconds_*` and
`ollama_tokens_total`. Ollama does not expose a Prometheus endpoint in the current
deployment; no scrape job exists for `ollama:11434`.

**Impact:** Inference request rate, latency, and token throughput for Ollama are not
visible in Grafana.

**Fix:** Confirm Ollama metrics endpoint availability (`docker exec ollama curl -s
http://localhost:11434/metrics`). Add scrape job to `prometheus.yml`. Verify actual
metric names and update `grafana/dashboards/ollama-inference.json`.

**Trigger:** Phase 5 supplement.

**Ref:** [ADR-0009](docs/decisions/adr/ADR-0009-observability-missing-metrics-sources.md)

---

### OBS-4 — LiteLLM Proxy Dashboard: Not on observability_internal

**What:** The `hal-litellm` dashboard queries LiteLLM metrics, but LiteLLM runs only
on `ai_internal` — unreachable from Prometheus on `observability_internal`. No scrape
job exists. Metric names in the dashboard are also placeholders that need verification.

**Impact:** LiteLLM request rate, token throughput, per-model routing, and error rate
are not visible in Grafana.

**Fix:** Attach LiteLLM container to `observability_internal` in
`compose/proxy/docker-compose.yml`. Add scrape job to `prometheus.yml`. Confirm actual
metric names (`curl -sk https://litellm.hal.local/metrics`) and update
`grafana/dashboards/litellm-proxy.json`.

**Trigger:** Phase 5 supplement.

**Ref:** [ADR-0009](docs/decisions/adr/ADR-0009-observability-missing-metrics-sources.md)

---

## GPU / VRAM

### GPU-1 — ROCm VRAM Ceiling: ~56 GB Actual vs. 96 GB Firmware Allocation

**What:** ROCm/HIP can only access ~56 GB of the 96 GB iGPU firmware allocation on the
AMD Radeon 8060S. The remaining ~40 GB may require XNACK/unified memory support or a
future ROCm driver update. Root cause is not fully confirmed with AMD documentation.

**Impact:** Multi-model scheduling is constrained. Running 2× 32B llama.cpp containers
(~46 GB) is the practical limit. Adding an Ollama 32B model simultaneously (~30 GB)
exceeds available VRAM.

**Fix:** Investigate BIOS iGPU memory allocation options, newer ROCm versions with better
Hawk Point support, and `AMDGPU_FORCE_VRAM_ALLOC_ONLY`. Report findings to AMD if this
is a driver gap.

**Trigger:** ROCm version upgrade or new AMD Strix Point / Hawk Point support documentation.

**Ref:** [ADR-0012](docs/decisions/adr/ADR-0012-vram-allocation-limits-amd-radeon-8060s.md)

---

### GPU-2 — Manual VRAM Coordination Between Ollama and llama.cpp

**What:** Ollama holds loaded models in VRAM until explicit unload or keep-alive TTL
(5 min default). It does not yield to ROCm memory pressure from llama.cpp containers,
which crash with OOM if both are loaded simultaneously beyond ~56 GB.

**Impact:** Starting llama.cpp containers requires manually stopping Ollama models first.
Error-prone under normal operator use.

**Fix options:**
- Set `OLLAMA_KEEP_ALIVE=0` in `compose/ai/` — Ollama releases VRAM immediately after
  each request, eliminating the manual unload step
- Add a pre-flight script that checks `rocm-smi` VRAM headroom before starting any
  llama.cpp container and fails fast with a clear error
- Define Docker Compose profiles for "chat mode" (Ollama only) vs. "agentic mode"
  (llama.cpp only)

**Trigger:** Any of the above can be implemented independently; `OLLAMA_KEEP_ALIVE=0`
is the lowest-effort option.

**Ref:** [ADR-0012](docs/decisions/adr/ADR-0012-vram-allocation-limits-amd-radeon-8060s.md)

---

### GPU-3 — llama.cpp HSA Override Segfault (11.0.2 → gfx1102) Not Upstreamed

**What:** llama.cpp build b8390 segfaults with `HSA_OVERRIDE_GFX_VERSION=11.0.2` on
AMD Radeon 8060S (gfx1102) during `sched_reserve`. Workaround is `11.0.0` (gfx1100
kernels). Root cause in the ROCm image is unknown and not reported upstream.

**Impact:** If a future llama.cpp image is pulled without verifying the workaround,
containers will crash on startup. The override difference between Ollama (11.0.2) and
llama.cpp (11.0.0) is a persistent source of confusion.

**Fix:** File an upstream issue with `ggml-org/llama.cpp` with the reproduction details
documented in ADR-0012 (F4). Monitor whether newer builds include compiled gfx1102
kernels that eliminate the segfault.

**Trigger:** Any llama.cpp image upgrade.

**Ref:** [ADR-0012](docs/decisions/adr/ADR-0012-vram-allocation-limits-amd-radeon-8060s.md)

---

## AI Serving

### AI-1 — llama.cpp Streaming Bug: tool_choice Hook is a Workaround

**What:** llama.cpp build b8390 fails to populate `tool_calls` in streaming responses
unless `tool_choice: "required"` is in the request. Without it, `<tool_call>` XML leaks
as plain `content` text with `finish_reason: stop`. The LiteLLM pre-call hook
(`compose/proxy/tool_choice_hook.py`) injects `tool_choice: "required"` as a workaround.

**Impact:** The hook is an extra moving part. If the upstream bug is fixed, the hook
becomes unnecessary overhead (harmless but should be removed for cleanliness).

**Fix:** After any llama.cpp image upgrade, run the monitoring script in ADR-0013 to
check if streaming tool_calls now work without `tool_choice: "required"`. If fixed:
remove the injection from `tool_choice_hook.py` and the
`model_info: supports_function_calling: true` overrides from `litellm-config.yaml`.

**Trigger:** Every llama.cpp image upgrade. Monitoring script is in ADR-0013.

**Ref:** [ADR-0013](docs/decisions/adr/ADR-0013-litellm-tool-choice-hook.md)

---

### AI-2 — LiteLLM Model DB: supports_function_calling Override Required

**What:** `litellm.supports_function_calling('openai/qwen2.5-coder:32b')` returns
`False`. The `model_info: supports_function_calling: true` override in
`litellm-config.yaml` is required to prevent `drop_params: true` from stripping the
`tools` array before it reaches llama.cpp.

**Impact:** If LiteLLM is upgraded and the model DB is updated to include these models,
the override becomes redundant (harmless but noisy config).

**Fix:** After any LiteLLM upgrade, verify with:
```bash
docker exec litellm python3 -c \
  "import litellm; print(litellm.supports_function_calling('openai/qwen2.5-coder:32b'))"
```
If `True`, remove the `model_info` overrides from the three `-tools` entries in
`litellm-config.yaml`.

**Trigger:** LiteLLM image upgrade.

**Ref:** [ADR-0013](docs/decisions/adr/ADR-0013-litellm-tool-choice-hook.md)

---

### AI-3 — GGUF Deduplication with Ollama Blobs

**What:** GGUF files in `/srv/platform/models/gguf/` are separate copies from Ollama's
content-addressed blobs at `/srv/platform/models/blobs/`. Both store the same model
weights — approximately 40 GB of duplicate disk usage for the two 32B models.

**Impact:** ~40 GB wasted disk on `/srv/platform` (1.35 TB partition — not urgent).

**Fix:** Script to detect duplicate weights between Ollama blobs and GGUF files and
replace GGUF files with symlinks into Ollama's blob store, or vice versa.

**Trigger:** Disk pressure on `/srv/platform`, or before adding additional models.

**Ref:** [ROADMAP.md](ROADMAP.md) — Backlog

---

## Infrastructure / Operations

### INF-1 — No Automated Backup Rotation

**What:** No backup rotation scripts exist. Application-level backups to
`/srv/platform/backups/` are not automated.

**Impact:** Backup management is fully manual. Risk of backup storage growing unbounded
or gaps in backup history going unnoticed.

**Fix:** `scripts/backup-rotate.sh` — implement with configurable retention, covering
Open WebUI data, ChromaDB (planned), and encrypted secrets.

**Trigger:** Before ChromaDB or n8n deployment (Phase 9/10).

**Ref:** [ROADMAP.md](ROADMAP.md) — Backlog

---

### INF-2 — No Secret Rotation Runbook

**What:** Secrets (LiteLLM master key, Open WebUI session key) were generated once
during bootstrap. No runbook exists for routine rotation or emergency rotation on
compromise.

**Impact:** Keys are never rotated in normal operation. A compromised key has no
documented response procedure.

**Fix:** `docs/runbooks/secret-rotation.md` — document rotation procedures for each
secret family (`proxy`, `ai`, `core`). The bare-bones rotation commands exist inline
in `docs/runbooks/ai-stack.md` (Section 8) but are not a standalone runbook.

**Trigger:** Before the platform is used for sensitive workloads, or after any
suspected compromise.

**Ref:** [ROADMAP.md](ROADMAP.md) — Backlog

---

### INF-3 — No Disaster Recovery Runbook

**What:** No documented procedure exists for full platform recovery from a hardware
failure or OS reinstall. Timeshift snapshots are configured but the restore-to-running-
platform procedure is undocumented.

**Fix:** `docs/runbooks/disaster-recovery.md` — full restore procedure: Timeshift
restore → SOPS key recovery → secrets decrypt → stack bring-up order.

**Trigger:** Before the platform hosts irreplaceable data (e.g., ChromaDB, n8n workflows).

**Ref:** [ROADMAP.md](ROADMAP.md) — Backlog

---

## Future Evaluations

### FUT-1 — vLLM Evaluation (Pending Discrete GPU)

**What:** vLLM was deferred as the primary inference backend in ADR-0011. It requires
ROCm support for discrete AMD GPUs and has not been tested on the Radeon 8060S iGPU.

**Trigger:** Hardware upgrade to a discrete AMD GPU (RX 7900 XTX or MI-series).

**Ref:** [ADR-0011](docs/decisions/adr/ADR-0011-llama-cpp-function-calling-stack.md), [ROADMAP.md](ROADMAP.md) — Backlog

---

### FUT-2 — Unified Inference Backend (Eliminate Ollama + llama.cpp Split)

**What:** The current dual-backend architecture (Ollama for chat, llama.cpp for tool
calling) exists because neither serves both use cases well on this hardware. If a future
backend supports both, VRAM contention and operational complexity are eliminated.

**Candidates:** vLLM (post discrete GPU), Ollama native tool calling (if added for RDNA
3.5), llama.cpp as sole backend (revisit if VRAM constraints worsen).

**Trigger:** Ollama adds native function calling support for RDNA 3.5, or hardware upgrade.

**Ref:** [ADR-0012](docs/decisions/adr/ADR-0012-vram-allocation-limits-amd-radeon-8060s.md)

---

## Summary

| ID | Area | Effort | Trigger |
|----|------|--------|---------|
| OBS-1 | cAdvisor / Docker storage driver | Medium (60 min downtime) | Maintenance window |
| OBS-2 | GPU/ROCm Grafana dashboard | Medium | Phase 5 supplement |
| OBS-3 | Ollama metrics endpoint | Low | Phase 5 supplement |
| OBS-4 | LiteLLM metrics / network | Low | Phase 5 supplement |
| GPU-1 | ROCm VRAM ceiling investigation | Research | ROCm upgrade |
| GPU-2 | VRAM coordination automation | Low–Medium | Any time |
| GPU-3 | llama.cpp HSA upstream report | Low | Next llama.cpp upgrade |
| AI-1 | llama.cpp streaming bug hook | Low (cleanup) | llama.cpp upgrade |
| AI-2 | LiteLLM model DB override | Low (cleanup) | LiteLLM upgrade |
| AI-3 | GGUF / Ollama deduplication | Medium | Disk pressure |
| INF-1 | Backup rotation scripts | Medium | Pre Phase 9/10 |
| INF-2 | Secret rotation runbook | Low | Before sensitive data |
| INF-3 | Disaster recovery runbook | Medium | Before sensitive data |
| FUT-1 | vLLM evaluation | Research | Discrete GPU upgrade |
| FUT-2 | Unified inference backend | Research | Ollama tool calling / GPU upgrade |
