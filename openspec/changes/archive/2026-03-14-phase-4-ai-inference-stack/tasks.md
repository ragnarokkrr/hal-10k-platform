## 1. Secrets & Configuration

- [x] 1.1 Create `secrets/ai.enc.yaml` template with `LITELLM_MASTER_KEY` and `LITELLM_SECRET_KEY` placeholders, then encrypt with SOPS
- [x] 1.2 Create `compose/ai/.env.example` with all required variables (LITELLM_MASTER_KEY, OLLAMA_HOST, image tags) — no real values
- [x] 1.3 Verify `compose/ai/.env` is listed in `.gitignore`

## 2. Docker Compose Stack

- [x] 2.1 Create `compose/ai/docker-compose.yml` with the `ollama` service: pinned ROCm image, `driver: amdgpu` GPU reservation, bind-mount `/srv/platform/models/:/root/.ollama/models`, `ai_internal` network only, healthcheck, `restart: unless-stopped`
- [x] 2.2 Add `litellm` service to `compose/ai/docker-compose.yml`: pinned image, master-key env var from `.env`, Ollama backend URL pointing to `http://ollama:11434`, `ai_internal` + `proxy` networks, healthcheck, `restart: unless-stopped`
- [x] 2.3 Add `open-webui` service to `compose/ai/docker-compose.yml`: pinned image, `OPENAI_API_BASE_URL=http://litellm:4000/v1`, `OPENAI_API_KEY` from env, named volume for data, `ai_internal` + `proxy` networks, Traefik labels, healthcheck, `restart: unless-stopped`
- [x] 2.4 Define networks in `compose/ai/docker-compose.yml`: `ai_internal` (internal bridge) and `proxy` (external, referencing the core stack network)
- [x] 2.5 Define named volumes in `compose/ai/docker-compose.yml`: `open_webui_data`

## 3. LiteLLM Configuration

- [x] 3.1 Create `compose/ai/litellm-config.yaml` (version-controlled, no secrets) listing the model roster: `qwen2.5-coder:32b`, `deepseek-r1:32b`, `llama3.3:70b` — all backed by `ollama/` provider pointing to `http://ollama:11434`
- [x] 3.2 Mount `litellm-config.yaml` into the LiteLLM container and set `LITELLM_CONFIG_PATH` env var

## 4. Traefik Routing

- [x] 4.1 Add Traefik labels to the Open WebUI service for HTTPS routing (router, service, TLS)
- [x] 4.2 Add Traefik labels to the LiteLLM service for HTTPS API routing
- [x] 4.3 Update `docs/ports.md` with Ollama (11434 internal), LiteLLM (4000 internal), and Open WebUI (3000 internal) entries

## 5. ADR

- [x] 5.1 Create `docs/decisions/adr/ADR-0006-llm-serving-ollama-litellm.md` documenting the choice of Ollama + LiteLLM over alternatives (vLLM, llama.cpp, direct Ollama exposure)

## 6. Deployment & Model Provisioning

- [x] 6.1 Decrypt secrets: run `scripts/secrets-decrypt.sh ai` and verify `/srv/platform/secrets/ai.yaml` exists with non-placeholder values
- [x] 6.2 Bring up the stack: `docker compose -f compose/ai/docker-compose.yml up -d`
- [x] 6.3 Verify Ollama GPU: check container logs for ROCm device detection and run `docker exec ollama ollama list`
- [x] 6.4 Pull model roster: ```docker exec ollama ollama pull qwen2.5-coder:32b
docker exec ollama ollama pull deepseek-r1:32b
docker exec ollama ollama pull llama3.3:70b```
- [x] 6.5 Smoke-test LiteLLM API: `curl -sk -H "Authorization: Bearer $LITELLM_MASTER_KEY" https://litellm.hal.local/models | jq '.data[].id'` — verify all three models appear. **Note**: requires `127.0.0.1 litellm.hal.local` in `/etc/hosts`; `-k` flag is required (self-signed cert). Verified: `qwen2.5-coder:32b`, `deepseek-r1:32b`, `llama3.3:70b` all returned.
- [x] 6.6 Verify Open WebUI: ensure `127.0.0.1 openwebui.hal.local` is in `/etc/hosts` (Traefik host rule is `openwebui.hal.local`), open `https://openwebui.hal.local` in a browser, accept the self-signed cert, create an admin account on first visit, confirm all three roster models appear in the model selector, and send a test message. **Note**: only one model loads at a time — switching models triggers an eviction; llama3.3:70b requires ~85 GiB and may be slow to swap in.

## 7. Runbooks & Documentation

- [x] 7.1 Create `docs/runbooks/ai-stack.md` — bring-up, teardown, GPU verification, stack restart steps
- [x] 7.2 Create `docs/runbooks/model-management.md` — pull, list, delete Ollama models; update LiteLLM config for new models
- [x] 7.3 Create `docs/runbooks/ai-client-setup.md` — configure Claude Code (`claude config`) and Cline to point at the LiteLLM proxy with the master key
- [x] 7.4 Update `docs/services-catalog.md` with Ollama, LiteLLM, and Open WebUI entries (image, port, network, volume, purpose)

## 8. ROADMAP Update

- [x] 8.1 Mark all Phase 4 checklist items as complete in `ROADMAP.md`
