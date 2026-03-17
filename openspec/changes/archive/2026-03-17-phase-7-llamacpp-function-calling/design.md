## Context

Phase 6 extracted LiteLLM into `compose/proxy/` as a standalone API gateway. The platform now has a clean multi-backend routing layer. However, agentic AI clients (Claude Code, OpenCode) remain non-functional against local models because Ollama does not support function/tool calling for any deployed model on RDNA 3.5 hardware.

ADR-0011 specifies llama.cpp as the solution: it implements function calling at the tokenisation layer using each model's embedded Jinja2 chat template (enabled by the `--jinja` server flag). The models themselves — qwen2.5-coder, llama3.3 — support tool calling natively; only the Ollama serving layer blocks it.

Current topology after Phase 6:

```
core (Traefik) → proxy (LiteLLM) → ai (Ollama + Open WebUI)
```

Target topology after Phase 7:

```
core (Traefik) → proxy (LiteLLM) → ai (Ollama + Open WebUI)
                                  → ai-tools (llama.cpp × N containers)
```

Constraints:
- Single AMD iGPU (40 CU RDNA 3.5), 128 GB total memory (32 GB system RAM + 96 GB dedicated VRAM)
- Ollama already has `MAX_LOADED_MODELS=1` and `NUM_PARALLEL=1`
- llama.cpp loads one model per process — multiple models require multiple containers
- `compose/ai-tools/` is operator-started on demand, not auto-started
- Operator selectively starts containers based on workload needs

## Goals / Non-Goals

**Goals:**
- Deploy llama.cpp as a function-calling capable inference backend in `compose/ai-tools/`
- Route `-tools` model aliases through LiteLLM to per-model llama.cpp containers
- Support running 2–3 models simultaneously via separate containers in `compose/ai-tools/`
- Document GGUF model download, verification, and GPU layer tuning
- Enable end-to-end agentic coding sessions (file edits, bash, codebase navigation) via local models
- Update client setup docs to document `-tools` model aliases

**Non-Goals:**
- Replacing Ollama (it stays for chat, model management, Open WebUI)
- Auto-starting `compose/ai-tools/` at boot (operator-controlled)
- GGUF deduplication with Ollama blobs (backlog item)
- vLLM evaluation (deferred per ADR-0011 until discrete GPU upgrade)
- Vulkan backend (HIP/ROCm is the primary path; Vulkan is a future experiment)

## Decisions

### D1: Container image — `ghcr.io/ggml-org/llama.cpp:server-rocm`

The official llama.cpp ROCm image ships both HIP and Vulkan compute paths. It is maintained by the ggml-org team and updated promptly after upstream releases.

**Alternative considered:** `rocm/llama.cpp` (AMD-published, pinned to specific ROCm releases). Rejected because: less frequent updates, and the official image already bundles ROCm support.

Image tag will be pinned in `.env.example` (never `latest`).

### D2: GGUF storage at `/srv/platform/models/gguf/`

GGUF files live in a new subdirectory alongside Ollama's managed storage:

```
/srv/platform/models/
├── blobs/         # Ollama-managed — do not touch
├── manifests/     # Ollama-managed — do not touch
└── gguf/          # llama.cpp models — manually curated
    ├── qwen2.5-coder-32b-instruct-q4_k_m.gguf   (~19 GB)
    ├── deepseek-r1-32b-q4_k_m.gguf              (~19 GB)
    └── llama3.3-70b-instruct-q4_k_m.gguf        (~40 GB)
```

All containers share the same bind-mount `/srv/platform/models/gguf/:/models:ro`. Each service references its specific model file via its hardcoded `--model` flag.

**Alternative considered:** Separate path at `/srv/platform/gguf/`. Rejected because: co-locating under `/srv/platform/models/` keeps all model weights on the same partition and simplifies backup scope.

### D3: Multi-container architecture — one service per model

llama.cpp loads a single model per process. To serve 2–3 models simultaneously, `compose/ai-tools/docker-compose.yml` defines one service per model:

| Service | Container | Model | Internal Port |
|---------|-----------|-------|---------------|
| `llama-cpp-qwen32b` | `llama-cpp-qwen32b` | qwen2.5-coder-32b-instruct Q4_K_M | 8080 |
| `llama-cpp-deepseek32b` | `llama-cpp-deepseek32b` | deepseek-r1-32b Q4_K_M | 8080 |
| `llama-cpp-llama70b` | `llama-cpp-llama70b` | llama3.3-70b-instruct Q4_K_M | 8080 |

Each container listens on port 8080 internally. Since they have unique hostnames on the `ai_internal` network, LiteLLM routes to each by container name (e.g., `http://llama-cpp-qwen32b:8080/v1`). No port conflicts.

A shared YAML anchor (`x-llama-base`) avoids duplicating GPU passthrough, ROCm env vars, and restart policy across services.

**Operator controls which models run:**
```bash
# Start specific models
docker compose -f compose/ai-tools/docker-compose.yml up -d llama-cpp-qwen32b llama-cpp-deepseek32b

# Start all
docker compose -f compose/ai-tools/docker-compose.yml up -d

# Stop one model to free RAM
docker compose -f compose/ai-tools/docker-compose.yml stop llama-cpp-llama70b
```

**Alternative considered:** Docker Compose profiles (`--profile qwen`, `--profile llama`). Rejected because: profiles add cognitive overhead and are less discoverable than simply naming services to `up -d`. The operator already knows which models to run.

**VRAM budget (approximate, Q4_K_M weights + FP16 KV cache, 96 GB dedicated VRAM):**

| Combination | Weights | + 16K ctx/ea | + 32K ctx/ea | Feasibility |
|-------------|---------|-------------|-------------|-------------|
| 1× 32B model | ~19 GB | ~23 GB | ~27 GB | Trivial |
| 2× 32B models | ~38 GB | ~46 GB | ~54 GB | Comfortable |
| 1× 32B + 1× 70B | ~62 GB | ~71 GB | ~80 GB | Comfortable |
| 2× 32B + 1× 70B | ~81 GB | ~94 GB | ~107 GB | Feasible at 16K; tight at 32K |

KV cache per token (FP16): ~0.25 MB for 32B models (64 layers, 8 GQA KV heads, 128 head dim), ~0.31 MB for 70B (80 layers). KV cache can be halved with `--cache-type-k q8_0 --cache-type-v q8_0` if needed.

For agentic coding (sequential tool calls), 8K–16K context is sufficient. Running all three models simultaneously at 16K is feasible within 96 GB VRAM.

### D4: Server flags — `--jinja --port 8080 --host 0.0.0.0`

The `--jinja` flag enables Jinja2 chat template rendering, which is the mechanism that enables function calling. Without it, tool definitions in the request are ignored.

Port 8080 is the llama.cpp default. It is NOT mapped to the host — only reachable via `ai_internal` network.

`--n-gpu-layers` is set per-service (default: 99, offload all layers to GPU). With 96 GB dedicated VRAM, all layers for all three models fit simultaneously — no partial offload needed.

`--ctx-size` defaults to 0 (model's native context). For multi-model scenarios, explicitly setting `--ctx-size 16384` per container keeps total VRAM under 96 GB with all three models loaded.

### D5: Network — `ai_internal` + `observability_internal`

`compose/ai-tools/` joins two external networks:
- `ai_internal` — for LiteLLM routing (inference requests in, responses out)
- `observability_internal` — for Prometheus scraping of `/metrics`

It does NOT join the `traefik` network — llama.cpp has no auth layer and must not be directly routable from the LAN. LiteLLM (in `compose/proxy/`) is the only inference entry point, authenticating via `LITELLM_MASTER_KEY`.

This follows the same dual-network pattern as Grafana (joins `observability_internal` + `traefik`). Prometheus reaches each container by hostname on port 8080 — the same port as the inference API, since llama.cpp serves both `/v1/chat/completions` and `/metrics` on a single port. Prometheus only reads `/metrics`; it does not call inference endpoints.

### D6: LiteLLM config — `-tools` suffix model aliases per container

Three new model entries in `compose/proxy/litellm-config.yaml`, each pointing to a dedicated container:

```yaml
# ── Tool-capable aliases — llama.cpp backends ─────────────────
- model_name: qwen2.5-coder:32b-tools
  litellm_params:
    model: openai/qwen2.5-coder:32b
    api_base: http://llama-cpp-qwen32b:8080/v1

- model_name: deepseek-r1:32b-tools
  litellm_params:
    model: openai/deepseek-r1:32b
    api_base: http://llama-cpp-deepseek32b:8080/v1

- model_name: llama3.3:70b-tools
  litellm_params:
    model: openai/llama3.3:70b
    api_base: http://llama-cpp-llama70b:8080/v1
```

Clients use the `-tools` suffix to opt into the function-calling backend. No client-side configuration changes beyond model name selection. If a backend container is not running, LiteLLM returns 502 for that alias and recovers automatically when it starts.

### D7: GPU passthrough — same pattern as Ollama

llama.cpp needs the same AMD GPU access as Ollama:
- Devices: `/dev/kfd`, `/dev/dri`
- Groups: `video` (44), `render` (992)
- Environment: `HSA_OVERRIDE_GFX_VERSION=11.0.0` (AMD Radeon 8060S / gfx1102)

**Note:** `11.0.0` (gfx1100), NOT `11.0.2` (gfx1102). While the device reports as gfx1102
and Ollama uses 11.0.2, llama.cpp's HIP kernel selection with 11.0.2 causes a segfault
in `sched_reserve` during context initialization. The 11.0.0 override selects gfx1100
kernels which are fully compatible with gfx1102 at the compute level and run correctly.

### D8: No secrets required

llama.cpp has no authentication mechanism. Security is enforced by network isolation: the container is only on `ai_internal`, and all external access goes through LiteLLM (which requires `LITELLM_MASTER_KEY`). No new SOPS secrets file is needed.

### D9: GGUF source — bartowski quantisations on Hugging Face

Recommended source: `bartowski` organisation on Hugging Face. These are pre-quantised, verified, and updated promptly after upstream model releases. Download via `huggingface-cli download`.

Quantisation: Q4_K_M for both models (best balance of quality and VRAM for 40 CU iGPU).

### D10: Observability — Prometheus scraping + Loki log driver

**Metrics:** llama.cpp exposes a Prometheus endpoint at `/metrics` (same port 8080). Three new static scrape jobs are added to `compose/observability/prometheus.yml`, one per container:

```yaml
- job_name: llama-cpp-qwen32b
  static_configs:
    - targets: ["llama-cpp-qwen32b:8080"]

- job_name: llama-cpp-deepseek32b
  static_configs:
    - targets: ["llama-cpp-deepseek32b:8080"]

- job_name: llama-cpp-llama70b
  static_configs:
    - targets: ["llama-cpp-llama70b:8080"]
```

These jobs are always present in `prometheus.yml`. When a container is not running, Prometheus marks the target as `DOWN` — no error, just a scrape miss. When the container starts, metrics appear automatically.

**Logging:** The global Docker Loki log driver (configured in `/etc/docker/daemon.json`) automatically ships all container stdout/stderr to Loki. No per-service config required. Logs are queryable in Grafana by label `{compose_service="llama-cpp-qwen32b"}`. Model loading progress, GPU device detection, and inference errors are all captured.

**Resolves ADR-0009 gap:** ADR-0009 documents that Ollama and LiteLLM metrics are not scraped because their containers are only on `ai_internal`, unreachable by Prometheus on `observability_internal`. Phase 7 solves this for llama.cpp by design (dual-network attachment). The same fix can be backported to Ollama/LiteLLM in a future phase.

**Key llama.cpp metrics available** (prefix: `llamacpp:`, enabled by `--metrics` flag):
- `llamacpp:prompt_tokens_total`, `llamacpp:tokens_predicted_total` — throughput
- `llamacpp:requests_processing`, `llamacpp:requests_deferred` — queue depth
- `llamacpp:kv_cache_usage_ratio` — VRAM pressure indicator
- `llamacpp:prompt_seconds_total`, `llamacpp:tokens_predicted_seconds_total` — latency

## Risks / Trade-offs

**[GPU contention — multi-model]** Running 2–3 llama.cpp containers plus Ollama all share the 40 CU iGPU. Simultaneous inference across models degrades throughput for all.
→ Mitigation: `compose/ai-tools/` is not auto-started. Operator selectively starts only the models needed. For interactive agentic work (sequential tool calls with idle periods), GPU compute contention is minimal.

**[Actual usable VRAM: ~56 GB, not 96 GB]** ROCm/HIP reports and can allocate ~56 GB of VRAM on this hardware (AMD Radeon 8060S). The full 128 GB (32 GB system + 96 GB iGPU allocation) is not fully accessible as ROCm VRAM — only the framebuffer portion (~56 GB) is. Practical limit: 2× 32B llama.cpp containers (~46 GB) fit comfortably; adding an Ollama 32B model simultaneously (~30 GB) exceeds available VRAM.
→ Mitigation: Coordinate model loading. Unload Ollama models (`keep_alive: 0`) before starting llama.cpp containers, or vice versa. This is an accepted hardware constraint.

**[VRAM pressure at large contexts]** Two 32B models at 32K context each would require ~54 GB, nearing the 56 GB limit.
→ Mitigation: Use `--ctx-size 16384` (sufficient for agentic tool calls). For single-model sessions, context can go up to 32K+ comfortably. KV cache quantization (`--cache-type-k q8_0 --cache-type-v q8_0`) halves cache overhead if more headroom is needed.

**[Disk usage]** GGUF files are separate from Ollama blobs. ~19 GB each for 32B models, ~40 GB for 70B — all additive to existing Ollama storage.
→ Mitigation: Accepted trade-off. GGUF deduplication script is a backlog item. Monitor `/srv` partition usage.

**[Manual GGUF management]** No equivalent to `ollama pull/rm/list`. Models managed manually via `hf` CLI (huggingface_hub).
→ Mitigation: Document download, verification, and cleanup in `docs/runbooks/gguf-model-setup.md`.

**[ROCm compatibility]** `HSA_OVERRIDE_GFX_VERSION=11.0.0` is required for llama.cpp on this GPU (different from Ollama's 11.0.2). If ROCm updates change kernel compatibility, test new image builds before promoting.
→ Mitigation: Pin image by digest. Test ROCm image upgrades in Distrobox experimentation layer before promoting to production.

**[LiteLLM api_key requirement]** LiteLLM's `openai/` model prefix requires an `api_key` in `litellm_params` even when the backend has no auth. This applies to both Ollama and llama.cpp backends.
→ Mitigation: Set `api_key: "ollama"` or `api_key: "llama"` (dummy values) in `litellm-config.yaml` for all `openai/` prefix entries.

**[Partial availability]** If some llama.cpp containers are stopped, those `-tools` aliases return 502 from LiteLLM. Clients see model-specific errors, not a global outage.
→ Mitigation: LiteLLM recovers automatically when a backend starts. Document expected behavior in client setup runbook.

## Migration Plan

1. Create `/srv/platform/models/gguf/` directory
2. Download GGUF models (can run in background while building compose stack)
3. Create `compose/ai-tools/docker-compose.yml` with per-model services and `.env.example`
4. Add per-container `-tools` aliases to `compose/proxy/litellm-config.yaml`
5. Bring up selected containers: `docker compose -f compose/ai-tools/docker-compose.yml up -d llama-cpp-qwen32b`
6. Restart LiteLLM to pick up config changes: `docker compose -f compose/proxy/docker-compose.yml restart litellm`
7. Verify function calling end-to-end per model
8. Update docs and runbooks

**Rollback:** Remove `-tools` aliases from litellm-config.yaml, restart LiteLLM, bring down `compose/ai-tools/`. No data loss — GGUF files can be deleted independently.
