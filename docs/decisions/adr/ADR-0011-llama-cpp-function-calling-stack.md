# ADR-0011: LiteLLM Extraction and llama.cpp Function-Calling Stack

**Date**: 2026-03-15
**Status**: Accepted

Supersedes: ADR-0006 (partially — inference backend decisions stand; compose topology revised)

---

## Context

ADR-0006 established Ollama as the inference backend for the HAL-10k AI stack and
co-located LiteLLM within `compose/ai/`. Both decisions were correct at the time.

During integration testing of agentic AI coding clients (Claude Code, OpenCode) against
the stack, two issues were discovered that together require a structural response:

### Issue 1 — Ollama Does Not Support Function Calling

None of the three Ollama-served models support OpenAI-compatible function/tool calling:

```
OllamaException - {"error":"\"qwen2.5-coder:32b\" does not support tools"}
OllamaException - {"error":"\"deepseek-r1:32b\" does not support tools"}
OllamaException - {"error":"\"llama3.3:70b\" does not support tools"}
```

This is not a configuration gap. Ollama's tool-call routing is tied to its internal
model registry metadata — a model must be explicitly tagged as tool-capable in Ollama's
registry to accept `tools` payloads. The models deployed on HAL-10k are not in that set
for RDNA 3.5 hardware, and this cannot be fixed without upstream Ollama changes.

The models themselves — qwen2.5-coder, deepseek-r1, llama3.3 — do support function
calling. Their GGUF chat templates encode tool-call formatting natively. The constraint
is entirely at the Ollama serving layer.

**Why this matters:** Agentic clients (Claude Code, OpenCode) do not simply prompt a
model and display output. They send the model a structured list of tools (read file,
write file, run bash, search codebase) as JSON, then parse the model's `tool_calls`
response to execute real actions. Without function calling, these clients degrade to
chat — the model describes what it would do, but nothing happens.

### Issue 2 — The Anthropic `thinking` Parameter

Claude Code sends an Anthropic-specific `thinking` parameter in `/v1/messages` requests.
Ollama interprets this as a request to enable chain-of-thought mode (`think: true`) and
rejects it for non-thinking models. A workaround was applied on 2026-03-15:

- LiteLLM upgraded from v1.23.9 to v1.81.12 (required to proxy `/v1/messages` at all)
- Model routes switched from `ollama/` to `openai/` provider prefix in LiteLLM
- `drop_params: true` added to `litellm_settings` to strip the `thinking` parameter

This workaround is live and effective. It does not resolve the tool-calling gap.

### Issue 3 — LiteLLM Co-location Creates Coupling

LiteLLM currently lives in `compose/ai/` alongside Ollama and Open WebUI. This creates
three problems as the stack grows:

1. **Restart coupling**: restarting LiteLLM to apply a config change (e.g., adding a
   new model route to llama.cpp) also interrupts the Ollama and Open WebUI dependency
   chain, even though those services are unaffected
2. **Ownership ambiguity**: `compose/ai/` owns both the inference layer (Ollama) and
   the API gateway (LiteLLM). Adding `compose/ai-tools/` would require LiteLLM to span
   two compose projects, which is awkward — LiteLLM must be reachable by both but
   owned by one
3. **Scaling surface**: any future backend (vLLM, additional llama.cpp instances) would
   need to modify `compose/ai/` even though it has nothing to do with Ollama

---

## Problem Statement

The HAL-10k AI stack has two functionally distinct inference workloads:

| Workload | Tool Calling Required | Current Status |
|----------|-----------------------|----------------|
| Browser chat (Open WebUI) | No | ✓ Working |
| Conversational Q&A (Claude Code chat, Python SDK) | No | ✓ Working |
| Agentic coding (file edits, bash, codebase navigation) | **Yes** | ✗ Blocked |

And one structural problem:

| Structural Issue | Impact |
|-----------------|--------|
| LiteLLM co-located with Ollama | Prevents clean multi-backend routing; creates restart coupling |

---

## Decision

Two changes are made, delivered as two separate specs:

### Spec 1 — Extract LiteLLM into `compose/proxy/`

LiteLLM is promoted from a component within `compose/ai/` to a standalone compose
stack at `compose/proxy/`. It becomes the platform-level API gateway, independent of
any inference backend.

`compose/ai/` is reduced to inference-only concerns: Ollama and Open WebUI.

### Spec 2 — Add `compose/ai-tools/` with llama.cpp

A new compose stack at `compose/ai-tools/` runs llama.cpp as a function-calling capable
inference backend. LiteLLM (now in `compose/proxy/`) routes tool-requiring model aliases
to llama.cpp and chat aliases to Ollama.

---

## Final Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Laptop Clients                                         │
│  Claude Code · OpenCode · Python SDK · curl             │
└───────────────────────┬─────────────────────────────────┘
                        │ HTTPS
                        ▼
┌───────────────────────────────────────────────────────┐
│  compose/core                                         │
│  Traefik  (litellm.hal.local / openwebui.hal.local)  │
└──────────┬────────────────────────┬───────────────────┘
           │                        │
           ▼                        ▼
┌──────────────────┐     ┌──────────────────────────────┐
│  compose/proxy   │     │  compose/ai                  │
│  LiteLLM :4000  │     │  Open WebUI :8080            │
│                  │     └──────────────────────────────┘
│  Routes:         │                 │ (via ai_internal)
│  *:32b (chat) ──────────┐         │
│  *:70b (chat) ──────────┤         │
│  *-tools ───────┐  ┌────▼─────────▼──────────────────┐
└─────────────────┘  │  compose/ai                     │
                     │  Ollama :11434                  │
                     │  (chat models)                  │
                     └────────────────────────────────┘
                         │
                    ┌────▼───────────────────────────────┐
                    │  compose/ai-tools                  │
                    │  llama.cpp :8080                  │
                    │  (tool-callable models)            │
                    └────────────────────────────────────┘
```

### Network Topology

Two Docker networks span the stacks:

| Network | Members | Purpose |
|---------|---------|---------|
| `traefik` (external) | Traefik, LiteLLM, Open WebUI | Public HTTPS routing |
| `ai_internal` (external) | LiteLLM, Ollama, llama.cpp, Open WebUI | Backend inference traffic |

Both networks are declared `external: true` in every compose file that uses them.
They are created once (by `compose/core/`) and shared across all stacks.

### Model Routing in LiteLLM

```yaml
# compose/proxy/litellm-config.yaml

model_list:

  # ── Chat models — Ollama backend ─────────────────────────────
  - model_name: qwen2.5-coder:32b
    litellm_params:
      model: openai/qwen2.5-coder:32b
      api_base: http://ollama:11434/v1

  - model_name: deepseek-r1:32b
    litellm_params:
      model: openai/deepseek-r1:32b
      api_base: http://ollama:11434/v1

  - model_name: llama3.3:70b
    litellm_params:
      model: openai/llama3.3:70b
      api_base: http://ollama:11434/v1

  # ── Tool-capable aliases — llama.cpp backend ─────────────────
  - model_name: qwen2.5-coder:32b-tools
    litellm_params:
      model: openai/qwen2.5-coder:32b
      api_base: http://llama-cpp:8080/v1

  - model_name: llama3.3:70b-tools
    litellm_params:
      model: openai/llama3.3:70b
      api_base: http://llama-cpp:8080/v1

litellm_settings:
  drop_params: true

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
```

Clients use the `-tools` suffix to opt into the function-calling backend:

```bash
# Chat — Ollama backend
claude --model qwen2.5-coder:32b "explain this function"
opencode --model hal/qwen2.5-coder:32b

# Agentic — llama.cpp backend (tool calling enabled)
opencode --model hal/qwen2.5-coder:32b-tools
```

### Startup Order

Cross-stack `depends_on` is not available in Docker Compose. Startup order is enforced
manually by the operator:

```bash
# 1. Gateway (must exist before any backend or client reaches LiteLLM)
docker compose -f compose/core/docker-compose.yml up -d

# 2. Inference backends (order between these two is arbitrary)
docker compose -f compose/ai/docker-compose.yml up -d
docker compose -f compose/ai-tools/docker-compose.yml up -d   # optional

# 3. API gateway (after backends are healthy)
docker compose -f compose/proxy/docker-compose.yml up -d
```

LiteLLM's liveness check (`/health/liveliness`) passes independently of backend health.
If a backend is not yet up, LiteLLM returns 502 for that model group and recovers
automatically when the backend becomes available — it does not crash or require restart.

---

## Why llama.cpp

### Function Calling Mechanism

llama.cpp implements function calling at the tokenisation layer using each model's
embedded Jinja2 chat template. When a client sends a `tools` array, llama.cpp:

1. Renders the tool definitions into the model's native prompt format via the chat template
2. Appends a generation instruction to emit a structured tool call
3. Parses the model's raw output back into an OpenAI-compatible `tool_calls` block

This is enabled by the `--jinja` server flag. No model modifications or fine-tuning
are required. The chat templates for qwen2.5-coder, llama3.3, and deepseek-r1 all
encode function calling natively in their GGUF metadata.

### ROCm / RDNA 3.5 Compatibility

llama.cpp supports AMD GPUs through two compute paths:

| Path | Mechanism | RDNA 3.5 Notes |
|------|-----------|----------------|
| HIP (ROCm) | Compiled against ROCm toolkit | Requires `HSA_OVERRIDE_GFX_VERSION=11.0.2` — same as Ollama |
| Vulkan | GPU-vendor-agnostic compute | Works natively on RDNA 3.5; no GFX override needed |

The official image `ghcr.io/ggml-org/llama.cpp:server-rocm` ships both paths.
AMD publishes `rocm/llama.cpp` pinned against specific ROCm releases as an alternative.

### Drop-in LiteLLM Compatibility

llama.cpp exposes `POST /v1/chat/completions` and `GET /v1/models` in full OpenAI
dialect. LiteLLM's `openai/` provider prefix integrates without modification — the same
pattern already in use for the Ollama thinking-parameter workaround.

---

## Trade-offs and Limitations

### Limitations of the Current Ollama Stack (Retained)

| Limitation | Impact | Status |
|------------|--------|--------|
| No function calling for any current model | Agentic clients non-functional | Addressed by this ADR (llama.cpp) |
| `thinking` parameter causes 500 errors | Claude Code fails | Mitigated: `drop_params: true` (live) |
| Tool support hardcoded in Ollama model registry | Cannot configure without upstream changes | Not addressable |
| LiteLLM v1.23.9 could not proxy `/v1/messages` | Claude Code auth loop | Fixed: upgraded to v1.81.12 (live) |

### LiteLLM Extraction Trade-offs

| Aspect | Before (co-located) | After (standalone) |
|--------|--------------------|--------------------|
| Restart scope | Restarts Ollama dependency chain | Restarts LiteLLM only |
| `depends_on` guarantee | LiteLLM waits for Ollama healthy | Manual startup order |
| Backend addition | Modify `compose/ai/` | Add new stack, update `litellm-config.yaml` |
| Config file location | `compose/ai/litellm-config.yaml` | `compose/proxy/litellm-config.yaml` |
| Failure isolation | LiteLLM crash affects Ollama restart logic | Fully isolated |

Loss of `depends_on` is acceptable: LiteLLM degrades gracefully when backends are
unavailable and recovers automatically. The operator startup sequence above replaces
the guarantee functionally.

### llama.cpp Trade-offs

**Advantages**

- Full OpenAI-compatible function calling for all three model families
- Mature RDNA 3.5 support via HIP and Vulkan
- Lightweight: lower idle memory footprint than Ollama
- Stateless: no persistent model registry; model is explicit at startup
- Zero client changes: `-tools` alias is transparent behind LiteLLM

**Disadvantages**

| Disadvantage | Severity | Detail |
|--------------|----------|--------|
| Models require GGUF format | Medium | Ollama's internal blobs are GGUF but content-addressed (SHA256 filenames); not directly usable. Separate download required. |
| No model management CLI | Medium | `ollama pull/rm/list` has no equivalent. Models managed manually via `huggingface-cli`. |
| One model per container | Medium | Serving two tool models simultaneously requires two containers. Only one is practical given the 40 CU GPU budget. |
| Manual quantisation selection | Low | Must choose Q4_K_M / Q5_K_M etc. explicitly. Recommended: Q4_K_M for 32B models, Q5_K_M for 70B if VRAM allows. |
| Duplicate disk storage | High | GGUFs for llama.cpp live separately from Ollama blobs. At Q4_K_M: qwen2.5-coder:32b ≈19 GB, llama3.3:70b ≈43 GB additive. |
| Manual startup | Low | `compose/ai-tools/` is not auto-started; operator brings it up when agentic work is needed. This is intentional (see GPU contention). |

### GGUF Storage Layout

```
/srv/platform/models/
├── blobs/         # Ollama-managed — content-addressed, opaque, do not touch
├── manifests/     # Ollama-managed — do not touch
└── gguf/          # llama.cpp models — manually curated
    ├── qwen2.5-coder-32b-instruct-q4_k_m.gguf   (~19 GB)
    └── llama3.3-70b-instruct-q4_k_m.gguf        (~43 GB)
```

Recommended GGUF source: `bartowski` organisation on Hugging Face. These are
pre-quantised, verified, and updated promptly after upstream model releases.

A future maintenance task (not in scope for either spec) could write a script to
extract and symlink GGUF blobs from Ollama's blob store, eliminating duplication.

### GPU Contention

Both Ollama and llama.cpp share the AMD iGPU (40 CU, RDNA 3.5, shared VRAM with
system RAM). Simultaneous inference will compete for compute and memory bandwidth.

Mitigations in place or required:

| Mitigation | Stack | Status |
|------------|-------|--------|
| `OLLAMA_MAX_LOADED_MODELS=1` | compose/ai | Already set |
| `OLLAMA_NUM_PARALLEL=1` | compose/ai | Already set |
| llama.cpp loads one model at startup | compose/ai-tools | Enforced by design |
| `compose/ai-tools/` not auto-started | compose/ai-tools | Operator-controlled |

For single-user interactive agentic work, contention is unlikely — Claude Code and
OpenCode generate tokens sequentially with idle periods between tool calls. The risk
materialises only if Open WebUI is actively used during an agentic session. The operator
should treat the GPU as a single-tenant resource and schedule accordingly.

### vLLM — Deferred

vLLM is the industry standard for high-throughput multi-user inference and has full
function calling support. It is not recommended at this time:

- ROCm support is production-grade for MI300X (HBM datacenter GPU), experimental for
  RDNA 3.5 (GDDR consumer iGPU)
- `HSA_OVERRIDE_GFX_VERSION` is not officially supported by the vLLM ROCm team
- KV cache, paged attention, and continuous batching require per-device calibration not
  validated for this hardware

Revisit vLLM in a future ADR if HAL-10k is upgraded to a discrete AMD GPU (RX 7900 XTX
or better) or a dedicated MI-series accelerator.

---

## Implementation Scope

This ADR is delivered in two specs:

### Spec 1: Extract LiteLLM → `compose/proxy/`

**Changes:**
- Create `compose/proxy/docker-compose.yml` — LiteLLM service with Traefik labels
- Create `compose/proxy/litellm-config.yaml` — migrated from `compose/ai/`
- Create `compose/proxy/.env.example` — LITELLM image tag, key references
- Remove LiteLLM service from `compose/ai/docker-compose.yml`
- Remove `depends_on: litellm` from Open WebUI in `compose/ai/docker-compose.yml`
- Update `compose/core/docker-compose.yml` to create `ai_internal` as a named network
  (currently implicit; must be explicit so external stacks can attach)
- Update all runbooks and docs that reference LiteLLM's compose location

**Verification:**
```bash
curl -sf https://litellm.hal.local/models | python3 -m json.tool
# All existing models still listed; Open WebUI still functional
```

### Spec 2: Add llama.cpp → `compose/ai-tools/`

**Changes:**
- Create `compose/ai-tools/docker-compose.yml` — llama.cpp service
- Create `compose/ai-tools/.env.example` — image tag, model path
- Add `-tools` model aliases to `compose/proxy/litellm-config.yaml`
- Create `docs/runbooks/gguf-model-setup.md` — GGUF download, verification, tuning
- Update `docs/runbooks/ai-client-setup.md` — document `-tools` model aliases,
  remove tool-use limitation notes that this resolves

**Verification:**
```bash
curl -sf https://litellm.hal.local/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder:32b-tools",
    "messages": [{"role": "user", "content": "list files in /tmp"}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "bash",
        "description": "Run a shell command",
        "parameters": {
          "type": "object",
          "properties": {"command": {"type": "string"}},
          "required": ["command"]
        }
      }
    }]
  }' | python3 -m json.tool
# Expect: tool_calls block in response, not an error
```

---

## Use Case Assignment

### Ollama (`compose/ai/`) — Keep For

- Open WebUI browser chat sessions
- Conversational coding Q&A without tool execution
- Python/SDK scripts that do not send `tools`
- Model lifecycle management (`ollama pull`, `ollama rm`, `ollama list`)
- Bulk prompting: summarisation, translation, explanation

Ollama's pull-and-run model management is its irreplaceable value. It remains the
primary inference backend for the majority of HAL-10k usage patterns.

### llama.cpp (`compose/ai-tools/`) — Use For

- OpenCode agentic sessions (file edits, bash, codebase navigation)
- Claude Code routed through local models via `ANTHROPIC_BASE_URL`
- Any OpenAI SDK client that sends a `tools` parameter
- Future MCP server backends that require structured function output
- Workloads where data residency matters and cloud inference is undesirable

`compose/ai-tools/` is brought up on demand, not at boot. When agentic work is done,
it can be stopped to release GPU resources back to Ollama.

---

## Consequences

**Positive**
- Agentic AI coding clients (Claude Code, OpenCode) become fully functional against local models
- LiteLLM is independently restartable and upgradeable without touching inference containers
- Adding a new inference backend in future requires only: a new compose stack + two lines in `litellm-config.yaml`
- No changes required to clients, Traefik, or auth — the API surface is unchanged
- Open WebUI is unaffected; Ollama chat paths continue working as before
- `compose/ai/` becomes a clean inference-only stack

**Negative**
- Loss of `depends_on` health guarantee between LiteLLM and Ollama (mitigated by LiteLLM's graceful degradation)
- Additional GGUF disk usage (~19–43 GB per model, separate from Ollama blobs)
- Manual GGUF download and update process
- Operator must manage startup order across four compose stacks
- GPU is a single-tenant resource; simultaneous Ollama + llama.cpp inference degrades both

**Neutral**
- `compose/ai-tools/` is intentionally not auto-started; this prevents accidental GPU contention

---

## Alternatives Considered

| Option | Verdict |
|--------|---------|
| Fix Ollama tool calling | Not feasible without upstream changes to Ollama's model registry |
| Keep LiteLLM in `compose/ai/`, extend to llama.cpp | Creates ambiguous ownership; LiteLLM routes to a backend in a different stack it does not own |
| vLLM with ROCm | Deferred — experimental on RDNA 3.5, calibration not validated |
| LocalAI (hipblas) | Viable but less mature than llama.cpp; no clear advantage |
| Retire Ollama, route everything through llama.cpp | Loses `ollama pull/rm/list` model management; operationally worse |
| Patch LiteLLM to silently strip `tools` before Ollama | Silently breaks agentic clients; unacceptable |
| Use cloud Claude for all agentic tasks | Valid fallback, already documented. This ADR provides the local-first alternative. |
