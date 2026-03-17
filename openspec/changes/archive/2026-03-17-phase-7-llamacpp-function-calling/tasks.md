## 1. GGUF Model Provisioning

- [x] 1.1 Create `/srv/platform/models/gguf/` directory on HAL-10k with appropriate ownership
- [x] 1.2 Download `Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf` from bartowski on Hugging Face using `hf download`; verified file size (19 GB)
- [x] 1.3 Download `DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf` from bartowski on Hugging Face; verified file size (19 GB)
- [x] 1.4 Download `Llama-3.3-70B-Instruct-Q4_K_M.gguf` from bartowski; verified file size (40 GB)

## 2. Create compose/ai-tools/ Stack

- [x] 2.1 Create `compose/ai-tools/docker-compose.yml` with a shared `x-llama-base` YAML anchor containing: pinned ROCm image `${LLAMACPP_IMAGE}`, GPU device passthrough (`/dev/kfd`, `/dev/dri`), `group_add` (44, 992), `HSA_OVERRIDE_GFX_VERSION=11.0.0`, bind-mount `/srv/platform/models/gguf/:/models:ro`, `ai_internal` and `observability_internal` as external networks, healthcheck polling `/health`, `restart: unless-stopped`, `--jinja --ctx-size ${CTX_SIZE:-16384}` in command
- [x] 2.2 Define service `llama-cpp-qwen32b` using `x-llama-base` anchor — command includes `--model /models/Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf --port 8080 --host 0.0.0.0 --jinja --n-gpu-layers ${N_GPU_LAYERS_QWEN32B:-99} --ctx-size ${CTX_SIZE:-16384}`, container_name `llama-cpp-qwen32b`
- [x] 2.3 Define service `llama-cpp-deepseek32b` using `x-llama-base` anchor — command includes `--model /models/DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf`, container_name `llama-cpp-deepseek32b`
- [x] 2.4 Define service `llama-cpp-llama70b` using `x-llama-base` anchor — command includes `--model /models/Llama-3.3-70B-Instruct-Q4_K_M.gguf`, container_name `llama-cpp-llama70b`
- [x] 2.5 Create `compose/ai-tools/.env.example` with `LLAMACPP_IMAGE`, `CTX_SIZE`, and per-model `N_GPU_LAYERS_*` placeholders
- [x] 2.6 Create `compose/ai-tools/.env` from `.env.example` with production values (gitignored)
- [x] 2.7 Verify `compose/ai-tools/.env` is covered by the existing `.gitignore` pattern `compose/*/.env`

## 3. Update LiteLLM Config and Observability

- [x] 3.1 Add `-tools` model aliases to `compose/proxy/litellm-config.yaml`: `qwen2.5-coder:32b-tools` → `http://llama-cpp-qwen32b:8080/v1`, `deepseek-r1:32b-tools` → `http://llama-cpp-deepseek32b:8080/v1`, `llama3.3:70b-tools` → `http://llama-cpp-llama70b:8080/v1`
- [x] 3.2 Add three static scrape jobs to `compose/observability/prometheus.yml`: `llama-cpp-qwen32b`, `llama-cpp-deepseek32b`, `llama-cpp-llama70b`, each targeting `<container-name>:8080`

## 4. Deploy and Verify

- [x] 4.1 Bring up primary model: `docker compose -f compose/ai-tools/docker-compose.yml up -d llama-cpp-qwen32b`; wait for healthy
- [x] 4.2 Restart LiteLLM to pick up config changes: `docker compose -f compose/proxy/docker-compose.yml restart litellm`; wait for healthy
- [x] 4.3 Verify llama-cpp-qwen32b health: `docker compose -f compose/ai-tools/docker-compose.yml ps` shows `(healthy)`
- [x] 4.4 Verify models endpoint: `curl -sk -H "Authorization: Bearer $LITELLM_MASTER_KEY" https://litellm.hal.local/models | jq '.data[].id'` — `-tools` aliases appear alongside existing models
- [x] 4.5 Verify function calling end-to-end: POST `/v1/chat/completions` to `qwen2.5-coder:32b-tools` with `tools` array → response contains `tool_calls`
- [x] 4.6 Bring up second model: `docker compose -f compose/ai-tools/docker-compose.yml up -d llama-cpp-deepseek32b`; verify both containers healthy simultaneously
- [x] 4.7 Verify existing chat models still work: POST to `qwen2.5-coder:32b` (no `-tools` suffix) returns normal completion via Ollama
- [x] 4.8 Verify Open WebUI still functional: open `https://openwebui.hal.local`, confirm models load and a test chat completes
- [x] 4.9 Verify Prometheus scraping: `docker exec prometheus wget -qO- http://llama-cpp-qwen32b:8080/metrics | grep llama_` returns llama.cpp metrics
- [x] 4.10 Verify Loki log ingestion: in Grafana Explore, query `{compose_service="llama-cpp-qwen32b"}` — model loading log lines appear

### 4.11–4.15 Llama 3.3 70B (optional — solo only, ~48 GB VRAM)

> **VRAM prerequisite**: stop both 32B containers and unload any Ollama model before starting the 70B. ~56 GB usable VRAM cannot hold 70B alongside any other loaded model.

- [x] 4.11 Free VRAM: `docker compose -f compose/ai-tools/docker-compose.yml stop llama-cpp-qwen32b llama-cpp-deepseek32b` and `curl -X POST http://localhost:11434/api/generate -d '{"model":"qwen2.5-coder:32b","keep_alive":0}'`; verify `docker exec ollama ollama ps` shows no loaded models
- [x] 4.12 Bring up 70B model: `docker compose -f compose/ai-tools/docker-compose.yml up -d llama-cpp-llama70b`; wait for `(healthy)` — model load takes 3–5 min
- [x] 4.13 Verify llama-cpp-llama70b health: `docker compose -f compose/ai-tools/docker-compose.yml ps` shows `(healthy)` and logs show `offloaded 81/81 layers to GPU`
- [x] 4.14 Verify function calling end-to-end: POST `/v1/chat/completions` to `llama3.3:70b-tools` with `tools` array → response contains `tool_calls`
- [x] 4.15 Restore 32B stack: `docker compose -f compose/ai-tools/docker-compose.yml stop llama-cpp-llama70b` and restart both 32B containers; verify both return to `(healthy)`

## 5. Documentation Updates

- [x] 5.1 Create `docs/runbooks/gguf-model-setup.md` — GGUF download via huggingface-cli, SHA256 verification, GPU layer tuning (`N_GPU_LAYERS_*`), VRAM budget table (weights + KV cache at 16K/32K) for model combinations on 96 GB VRAM
- [x] 5.2 Update `docs/runbooks/ai-client-setup.md` — document `-tools` model aliases for OpenCode and Claude Code; remove tool-use limitation notes resolved by this phase
- [x] 5.3 Update `docs/runbooks/ai-stack.md` — reflect five-stack topology (core → ai + ai-tools + proxy), note ai-tools is optional/on-demand with selective service startup, update startup and teardown order
- [x] 5.4 Update `docs/ports.md` — add llama.cpp row: port 8080, `compose/ai-tools`, internal only (multiple containers, same port)
- [x] 5.5 Create `docs/testcases/test-phase-7-llamacpp-function-calling.md` — test cases for function calling, multi-model routing, GPU access, network isolation, selective startup/stop, Prometheus scraping, Loki log ingestion
- [x] 5.6 Update `ROADMAP.md` — mark all Phase 7 checklist items as `[x]`
