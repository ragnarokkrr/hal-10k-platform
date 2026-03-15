## 1. Secrets Provisioning

- [x] 1.1 Create plaintext template `/tmp/proxy-secrets.yaml` with keys `LITELLM_MASTER_KEY` (same value as in current `secrets/ai.enc.yaml`) and `LITELLM_SECRET_KEY`; encrypt with SOPS: `sops --encrypt /tmp/proxy-secrets.yaml > secrets/proxy.enc.yaml`; verify with `git diff secrets/proxy.enc.yaml`
- [x] 1.2 Decrypt to runtime path: `./scripts/secrets-decrypt.sh proxy` and verify `/srv/platform/secrets/proxy.yaml` exists with correct keys
- [x] 1.3 Verify `secrets/proxy.enc.yaml` is tracked in git and the plaintext `/srv/platform/secrets/proxy.yaml` is NOT tracked (covered by `.gitignore` pattern `secrets/*.yaml`)

## 2. Network Preparation

- [x] 2.1 ~~Add `ai_internal` to `compose/core/`~~ — reverted; `compose/ai/` owns the network (Option B: Compose does not create unattached network declarations)
- [x] 2.2 Network will be created with correct name when `compose/ai/` is brought up in §5 (task 4.3 adds `name: ai_internal` to the `ai_internal` network declaration in `compose/ai/`)

## 3. Create compose/proxy/ Stack

- [x] 3.1 Create `compose/proxy/docker-compose.yml` with the `litellm` service: pinned image `${LITELLM_IMAGE:-ghcr.io/berriai/litellm:main-v1.81.12-stable.1}`, command `--config /app/config.yaml --port 4000 --num_workers 1`, `env_file: /srv/platform/secrets/proxy.yaml`, config volume mount, both `traefik` and `ai_internal` as external networks, healthcheck polling `/health/liveliness`, Traefik labels for `Host(litellm.hal.local)`, `restart: unless-stopped`
- [x] 3.2 Create `compose/proxy/litellm-config.yaml` — copy content verbatim from `compose/ai/litellm-config.yaml`; update the header comment to reflect the new stack location
- [x] 3.3 Create `compose/proxy/.env.example` with `LITELLM_IMAGE=ghcr.io/berriai/litellm:main-v1.81.12-stable.1`
- [x] 3.4 Verify `compose/proxy/.env` is covered by the existing `.gitignore` pattern `compose/*/.env`

## 4. Update compose/ai/ Stack

- [x] 4.1 Remove the entire `litellm` service block from `compose/ai/docker-compose.yml`
- [x] 4.2 Remove `depends_on: litellm` from the `open-webui` service in `compose/ai/docker-compose.yml`
- [x] 4.3 In `compose/ai/docker-compose.yml` networks section: keep `ai_internal` as the owner (not external) but add `name: ai_internal` so Docker creates the network with that exact name (not the project-prefixed `ai_ai_internal`)
- [x] 4.4 Delete `compose/ai/litellm-config.yaml` (content moved to `compose/proxy/`)
- [x] 4.5 Remove `LITELLM_IMAGE` from `compose/ai/.env.example` (LiteLLM now lives in proxy stack)

## 5. Migration Deployment

- [x] 5.1 Bring down the current ai stack: `docker compose -f compose/ai/docker-compose.yml down`
- [x] 5.2 Bring up updated ai stack (Ollama + Open WebUI only): `docker compose -f compose/ai/docker-compose.yml up -d`
- [x] 5.3 Bring up new proxy stack: `docker compose -f compose/proxy/docker-compose.yml up -d`
- [x] 5.4 Verify LiteLLM is healthy: `docker compose -f compose/proxy/docker-compose.yml ps` shows `(healthy)`
- [x] 5.5 Verify models endpoint: `curl -sk -H "Authorization: Bearer $LITELLM_MASTER_KEY" https://litellm.hal.local/models | jq '.data[].id'` — all three models appear
- [x] 5.6 Verify Open WebUI: open `https://openwebui.hal.local`, confirm models load and a test chat message completes end-to-end

## 6. Documentation Updates

- [x] 6.1 Update `docs/runbooks/ai-stack.md` — reflect new four-stack topology (core → ai + proxy), new startup order (core → ai → proxy), new teardown order (proxy → ai → core), note LiteLLM is now in a separate stack; add step to decrypt proxy secrets (`scripts/secrets-decrypt.sh proxy`)
- [x] 6.2 Update `docs/ports.md` — reassign the LiteLLM row from `compose/ai/` to `compose/proxy/`
- [x] 6.3 Create `docs/runbooks/test-phase-6-proxy-extraction.md` — step-by-step user test case covering: (a) verify `ai_internal` network exists and both `litellm` and `ollama` containers are attached; (b) verify `compose/ai/` has no litellm container; (c) verify LiteLLM models endpoint lists all three models; (d) verify Open WebUI chat completes a round-trip via the proxy; (e) verify Traefik routes `litellm.hal.local` and `openwebui.hal.local` independently; (f) verify proxy stack can restart without affecting `compose/ai/`
- [x] 6.4 Update `ROADMAP.md` — mark all Phase 6 checklist items as `[x]`

## 7. OpenSpec Archive

- [x] 7.1 Run `openspec archive --change phase-6-litellm-proxy-stack` to archive the change and merge delta specs into `openspec/specs/`
