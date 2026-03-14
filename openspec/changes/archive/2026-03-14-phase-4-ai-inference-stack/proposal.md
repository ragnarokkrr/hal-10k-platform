## Why

The HAL-10k platform has a functioning reverse proxy (Phase 3) but no AI serving layer yet. Phase 4 deploys the full LLM inference stack — Ollama, LiteLLM proxy, and Open WebUI — so the platform can host and serve local models for personal and agentic use, and so Claude Code and Cline can be pointed at local models via the LiteLLM OpenAI-compatible API.

## What Changes

- New `compose/ai/docker-compose.yml` Compose stack with three services: Ollama (model runner), LiteLLM (OpenAI-compatible proxy), and Open WebUI (browser chat interface)
- GPU device reservation via `driver: amdgpu` with ROCm environment variables for Ollama
- SOPS-encrypted `secrets/ai.enc.yaml` holding LiteLLM master key and any upstream API keys
- Traefik routing rules for Open WebUI and LiteLLM API endpoints (behind auth middleware)
- Initial model roster pulled and verified: Qwen2.5-Coder-32B, DeepSeek-R1-32B, Llama-3.3-70B-Instruct
- ADR-0006 documenting the LLM serving architecture decision (Ollama + LiteLLM)
- Runbook: `docs/runbooks/ai-stack.md` — bring-up, teardown, GPU verification
- Runbook: `docs/runbooks/model-management.md` — pull, list, delete Ollama models
- Runbook: `docs/runbooks/ai-client-setup.md` — configure Claude Code and Cline to use LiteLLM proxy

## Capabilities

### New Capabilities

- `ollama-inference`: Local GPU-accelerated LLM inference via Ollama; manages model weights at `/srv/platform/models/`
- `litellm-proxy`: OpenAI-compatible API gateway that routes requests to Ollama (and optionally upstream providers); protected by master-key auth
- `open-webui`: Browser-based chat interface connected to LiteLLM; exposed via Traefik with authentication

### Modified Capabilities

- `traefik-core-proxy`: New router and service entries for Open WebUI and LiteLLM API endpoints; no requirement-level changes, only configuration additions

## Impact

- **New Docker network**: `ai` stack joins the existing `proxy` network so Traefik can route to it
- **GPU**: Ollama requires AMD GPU reservation; no other service currently uses the GPU
- **Storage**: Model weights land at `/srv/platform/models/` (bind-mount into Ollama container); expected 20–100 GB per model
- **Ports** (internal only, exposed via Traefik): Ollama `:11434`, LiteLLM `:4000`, Open WebUI `:3000`
- **Secrets**: `secrets/ai.enc.yaml` — SOPS-encrypted; decrypted at runtime by `scripts/secrets-decrypt.sh`
- **Docs to update**: `docs/services-catalog.md`, `docs/ports.md`
- **New ADR**: ADR-0006
