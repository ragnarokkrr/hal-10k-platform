## Why

Agentic AI coding clients (Claude Code, OpenCode) require OpenAI-compatible function/tool calling to perform file edits, bash execution, and codebase navigation against local models. Ollama does not support tool calling for any of the deployed models on RDNA 3.5 hardware (see ADR-0011). llama.cpp implements function calling at the tokenisation layer using each model's embedded Jinja2 chat template, bypassing Ollama's limitation entirely.

Phase 6 extracted LiteLLM into `compose/proxy/` specifically to enable multi-backend routing. This phase adds the second backend.

## What Changes

- Create `compose/ai-tools/docker-compose.yml` — one llama.cpp service per model (e.g., `llama-cpp-qwen32b`, `llama-cpp-deepseek32b`, `llama-cpp-llama70b`), ROCm image, `--jinja` flag, shared YAML anchor for common GPU config
- Create `compose/ai-tools/.env.example` — image tag, per-model GPU layer config
- Create `/srv/platform/models/gguf/` directory for manually-curated GGUF model weights
- Download initial GGUF models (bartowski Q4_K_M quantisations): `qwen2.5-coder-32b-instruct` (~19 GB), `deepseek-r1-32b` (~19 GB), optionally `llama3.3-70b-instruct` (~43 GB)
- Add per-container `-tools` model aliases to `compose/proxy/litellm-config.yaml` routing each to its dedicated llama.cpp container
- Create `docs/runbooks/gguf-model-setup.md` — GGUF download, verification, GPU layer tuning
- Update `docs/runbooks/ai-client-setup.md` — document `-tools` model aliases for agentic clients, remove tool-use limitation notes
- Update `docs/ports.md` — add llama.cpp port assignment
- Create test case document for end-to-end function calling verification
- Mark Phase 7 items complete in `ROADMAP.md`

## Capabilities

### New Capabilities
- `llamacpp-function-calling`: llama.cpp inference server with OpenAI-compatible function/tool calling, deployed as `compose/ai-tools/` with ROCm GPU acceleration and GGUF model management

### Modified Capabilities
- `litellm-proxy-standalone`: Adding `-tools` model aliases that route to the llama.cpp backend on `ai_internal` network

## Impact

- **Compose stacks**: New `compose/ai-tools/` stack; modified `compose/proxy/litellm-config.yaml`
- **Networks**: `ai_internal` gains up to 3 new members (per-model llama-cpp containers)
- **Disk**: ~19–43 GB per GGUF model in `/srv/platform/models/gguf/` (separate from Ollama blobs)
- **GPU**: Shared AMD iGPU (40 CU RDNA 3.5), 96 GB dedicated VRAM — all three models can run simultaneously with 16K context each (~94 GB VRAM)
- **Memory**: 128 GB total (32 GB system RAM + 96 GB dedicated VRAM); weights + KV cache reside in VRAM, system RAM handles OS + Docker overhead
- **Secrets**: No new secrets required — llama.cpp has no auth layer; access is controlled by network isolation (ai_internal only)
- **Startup order**: `core → ai → ai-tools (optional) → proxy` (documented in runbooks)
- **Clients**: No client changes — `-tools` suffix is transparent behind LiteLLM
