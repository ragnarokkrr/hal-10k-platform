## Context

Traefik is running and healthy (Phase 3). The `proxy` Docker network exists and is the established ingress path for all services. The platform has a dedicated `/srv/platform/models/` directory for model weights. The GPU (AMD RDNA 3.5, 40 CU) is available but unused by any current service. SOPS + age is established for secret management.

The AI stack must fit within the single-node, no-Kubernetes constraint and surface an OpenAI-compatible API so external tools (Claude Code, Cline, any OpenAI-SDK client) can use local models without code changes.

## Goals / Non-Goals

**Goals:**
- Deploy Ollama as the GPU-accelerated model runner with ROCm support
- Deploy LiteLLM as an OpenAI-compatible proxy fronting Ollama
- Deploy Open WebUI as a browser chat interface
- Route both Open WebUI and LiteLLM API through Traefik with TLS
- Encrypt secrets (LiteLLM master key) with SOPS; never commit plaintext
- Pull and verify initial model roster: Qwen2.5-Coder-32B, DeepSeek-R1-32B, Llama-3.3-70B-Instruct
- Document client configuration for Claude Code and Cline

**Non-Goals:**
- Multi-GPU or distributed inference
- Upstream cloud LLM routing through LiteLLM (local-only for now)
- Fine-tuning or training workloads (Experimentation Layer, Phase 9)
- Observability dashboards (Phase 5 will add Ollama/LiteLLM metrics)

## Decisions

### D1: Ollama as the model runner (not vLLM, llama.cpp, or LM Studio)

Ollama provides a clean REST API, first-class ROCm support via official Docker images, and a simple model management CLI (`ollama pull`, `ollama list`). vLLM has stronger throughput for multi-user scenarios but requires more tuning and has less mature AMD GPU support at this platform's scale. llama.cpp and LM Studio are better suited to the Experimentation Layer (Distrobox), not the Platform Layer (Docker). **Decision: Ollama.**

### D2: LiteLLM as the OpenAI-compatible proxy layer

Tools like Claude Code and Cline speak OpenAI's API dialect. LiteLLM provides a drop-in proxy that translates OpenAI requests to Ollama's native API, adds master-key auth, per-model routing, and a spend-tracking UI. The alternative (exposing Ollama directly) would require patching every client and has no auth layer. **Decision: LiteLLM in proxy mode, master key auth, Ollama as the sole backend.**

### D3: Open WebUI connected to LiteLLM (not directly to Ollama)

Connecting Open WebUI through LiteLLM (instead of directly to Ollama) means all traffic — browser and API clients — flows through the same auth/routing layer. This simplifies future model additions and lets us observe unified usage. The slight latency overhead (~1 ms) is negligible for interactive use. **Decision: Open WebUI → LiteLLM → Ollama.**

### D4: Separate `ai` Compose stack, joined to the shared `proxy` network

Following the pattern established in Phase 3, each functional group is its own Compose project. The `ai` stack attaches to the externally-defined `proxy` network so Traefik can discover its containers. Internal service-to-service communication (Open WebUI → LiteLLM → Ollama) uses a private `ai_internal` network not exposed to Traefik. **Decision: two networks — `proxy` (external) and `ai_internal` (stack-private).**

### D5: Model weights at `/srv/platform/models/` (bind-mount, not Docker volume)

Model files are large (20–100 GB each), shared across possible future inference containers, and need to survive container/image rebuilds. A named Docker volume would obscure the path and complicate external tooling. A bind-mount at a well-known host path keeps management simple. **Decision: bind-mount `/srv/platform/models/` → `/root/.ollama/models` inside the Ollama container.**

### D6: Image version pinning strategy

- Ollama: pin to a specific SHA or minor version tag (e.g., `ollama/ollama:0.9.0-rocm`)
- LiteLLM: pin to a specific release tag (e.g., `ghcr.io/berriai/litellm:main-v1.72.0`)
- Open WebUI: pin to a specific release tag (e.g., `ghcr.io/open-webui/open-webui:v0.6.0`)

`latest` is never used in production per platform convention.

## Risks / Trade-offs

**[Risk] ROCm image compatibility with host ROCm 7.2** → Use the `-rocm` tagged Ollama image and verify `HSA_OVERRIDE_GFX_VERSION` if needed for RDNA 3.5. Include a GPU smoke test (`ollama run qwen2.5-coder:7b` with a trivial prompt) in the runbook.

**[Risk] Model weights fill `/srv/platform/` partition** → Document current partition size in the runbook; add a note on `docs/ports.md` to track storage. Phase 5 Grafana will add a disk alert.

**[Risk] LiteLLM master key exposed in env file** → Master key lives only in `secrets/ai.enc.yaml`, decrypted at runtime. The `.env` file is gitignored. The `.env.example` contains only placeholder values.

**[Risk] Open WebUI data persistence** → User accounts, chat history, and RAG documents must survive container restarts. Use a named Docker volume for Open WebUI's data directory.

**[Trade-off] LiteLLM adds one network hop** → Accepted; latency is imperceptible for interactive use and the proxy benefits (auth, routing, observability hooks) outweigh the cost.

## Migration Plan

1. Decrypt secrets: `scripts/secrets-decrypt.sh ai`
2. `docker compose -f compose/ai/docker-compose.yml up -d`
3. Verify Ollama GPU: `docker exec ollama ollama list` and inspect logs for ROCm device detection
4. Pull initial models: `ollama pull qwen2.5-coder:32b`, `ollama pull deepseek-r1:32b`, `ollama pull llama3.3:70b`
5. Smoke-test LiteLLM API: `curl -H "Authorization: Bearer $LITELLM_MASTER_KEY" http://localhost:4000/models`
6. Verify Open WebUI reachable via Traefik at configured hostname
7. Configure Claude Code and Cline per `docs/runbooks/ai-client-setup.md`

**Rollback**: `docker compose -f compose/ai/docker-compose.yml down` — model weights at `/srv/platform/models/` are unaffected.

## Open Questions

- **Exact image tags to pin**: Confirm latest stable tags for Ollama ROCm, LiteLLM, and Open WebUI at time of implementation.
- **Traefik hostnames**: Confirm subdomain conventions (e.g., `chat.hal`, `api.hal`) — or use path-based routing under a single hostname.
- **LiteLLM config file vs env vars**: LiteLLM supports a `config.yaml` for model routing; determine whether to use file-based config (version-controlled, minus secrets) or pure env-var config.
