## Context

Traefik (core), Ollama + LiteLLM + Open WebUI (ai), and Observability stacks are running. LiteLLM currently lives in `compose/ai/` alongside the inference containers. The `ai_internal` Docker network is currently created implicitly by the `ai` compose project with no explicit `name:` override, making it opaque to other stacks.

Phase 7 (llama.cpp function-calling stack) requires LiteLLM to route to both Ollama and llama.cpp backends simultaneously. This is impossible while LiteLLM is owned by the `ai` compose project.

Constraints: single-node, no Kubernetes, Docker CE + Compose v2, SOPS secrets, ADR-0011 accepted.

## Goals / Non-Goals

**Goals:**
- Move LiteLLM from `compose/ai/` to `compose/proxy/` with zero functional regression
- Establish `ai_internal` as an explicitly named Docker network created by `compose/core/`
- Remove unsupported cross-stack `depends_on`
- Preserve all model routes, auth, and Traefik routing unchanged

**Non-Goals:**
- Adding llama.cpp routes or new model aliases (Phase 7)
- Changing the LiteLLM config content or model roster
- Changing Open WebUI's backend URL (`http://litellm:4000/v1` stays identical)

## Decisions

### D1: `compose/ai/` owns `ai_internal` with `name: ai_internal`; `compose/proxy/` references it as external

Docker Compose prefixes networks with the project name unless `name:` is set. `compose/ai/` declares `ai_internal:` with `name: ai_internal` (no `external: true`), which causes Docker to create a network named literally `ai_internal` when the ai stack starts. `compose/proxy/` declares it as `external: true` with `name: ai_internal`. Natural dependency: `compose/ai/` must be running before `compose/proxy/` starts.

**Alternative considered:** Declaring the network in `compose/core/` so it exists earlier in the startup sequence. Rejected — Docker Compose does not create networks in the `networks:` section unless at least one service in the same file references that network. Since no core service attaches to `ai_internal`, the block would be silently ignored.

**Alternative considered:** A `scripts/create-ai-internal-network.sh` script (mirrors the `traefik` pattern). Rejected — the `traefik` network needs a script because it must exist *before* core starts and Traefik binds to it at boot. `ai_internal` only needs to exist before `compose/proxy/` starts, which is after `compose/ai/`. Compose ownership is simpler and keeps the network lifecycle inside the compose dependency graph.

### D2: `compose/proxy/` gets a dedicated `secrets/proxy.enc.yaml` SOPS file

LiteLLM requires `LITELLM_MASTER_KEY` and `LITELLM_SECRET_KEY`. These are gateway credentials — they belong to the proxy stack, not the inference stack, and should not live in `secrets/ai.enc.yaml` alongside Open WebUI's `WEBUI_SECRET_KEY`.

A new `secrets/proxy.enc.yaml` is created and encrypted with the same age key. At runtime, `scripts/secrets-decrypt.sh proxy` decrypts it to `/srv/platform/secrets/proxy.yaml`. `compose/proxy/` uses `env_file: /srv/platform/secrets/proxy.yaml`.

`secrets/ai.enc.yaml` retains `LITELLM_MASTER_KEY` for Open WebUI (which uses it as its `OPENAI_API_KEY` to authenticate to LiteLLM) and `WEBUI_SECRET_KEY`. No key rotation is required — the master key value is unchanged; it is simply also referenced from the new proxy secrets file.

**Alternative considered:** Reuse `secrets/ai.yaml` unchanged for `compose/proxy/`. Rejected — binds the proxy stack's credential lifecycle to the inference stack. Rotating or re-encrypting `ai.enc.yaml` silently affects the proxy stack, and vice versa. Separate files give each stack independent secret management.

### D3: No `depends_on` from Open WebUI to LiteLLM

Docker Compose `depends_on` only works within the same compose project. After extraction, LiteLLM and Open WebUI live in different projects. LiteLLM degrades gracefully: if Ollama is unreachable it returns 503 rather than crashing. Open WebUI will show a backend error until the proxy stack is running. The startup order is documented in the runbook, not enforced by compose.

### D4: `litellm-config.yaml` moves to `compose/proxy/` verbatim

The config content (three Ollama-backed models, `drop_params: true`, master_key from env) is unchanged. The Ollama `api_base: http://ollama:11434/v1` remains valid because Ollama's container name is `ollama` and both compose projects share the `ai_internal` network — Docker's per-network DNS resolves service names across projects on the same bridge.

## Risks / Trade-offs

**[Risk] Open WebUI starts before LiteLLM is healthy** → Operator must bring up `compose/proxy/` before testing chat. Document startup order: core → ai → proxy. LiteLLM reconnect is automatic; no Open WebUI restart needed.

**[Risk] `ai_internal` network deleted if `compose/core/` is downed while ai/proxy stacks are attached** → Docker refuses to remove a network with active endpoints. The network survives as long as any container is attached. Runbook specifies teardown order: proxy → ai → core.

**[Risk] Docker DNS resolution across projects** → The `litellm` hostname must resolve from Open WebUI on the shared `ai_internal` network. Docker resolves service names (not project-qualified names) on bridge networks. `litellm` service in `compose/proxy/` creates container name `litellm`, resolvable by all containers on `ai_internal`. Verified pattern matches Traefik's cross-project routing.

**[Trade-off] Manual startup order** → Loss of cross-project `depends_on`. Accepted per ADR-0011. Impact is limited to initial platform boot; LiteLLM's graceful degradation prevents cascading failures.

## Migration Plan

1. Apply compose file changes (do not restart yet)
2. Bring down ai stack: `docker compose -f compose/ai/docker-compose.yml down`
3. Restart core to create `ai_internal`: `docker compose -f compose/core/docker-compose.yml up -d`
4. Bring up updated ai stack: `docker compose -f compose/ai/docker-compose.yml up -d`
5. Bring up proxy stack: `docker compose -f compose/proxy/docker-compose.yml up -d`
6. Verify: models endpoint, Open WebUI chat

**Rollback:** `git stash` compose changes, bring down ai + proxy, bring up original ai stack (which still has LiteLLM). Model weights and Open WebUI data are unaffected.
