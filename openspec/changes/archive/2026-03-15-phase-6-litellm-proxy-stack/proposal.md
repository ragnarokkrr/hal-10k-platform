## Why

LiteLLM is co-located in `compose/ai/` alongside Ollama and Open WebUI. This coupling prevents adding new inference backends (Phase 7 llama.cpp) without modifying the inference stack, and causes unnecessary restart churn when gateway config changes. Extracting LiteLLM into `compose/proxy/` makes it the platform's permanent API gateway layer, independent of any backend.

## What Changes

- New `compose/proxy/docker-compose.yml` — LiteLLM service with Traefik labels and `ai_internal` external network
- New `compose/proxy/litellm-config.yaml` — migrated and updated from `compose/ai/litellm-config.yaml`
- New `compose/proxy/.env.example` — LiteLLM image tag and secrets references
- New `secrets/proxy.enc.yaml` — SOPS-encrypted LiteLLM gateway credentials (`LITELLM_MASTER_KEY`, `LITELLM_SECRET_KEY`), separate from the inference stack's `secrets/ai.enc.yaml`
- `compose/core/docker-compose.yml` — add explicit `ai_internal` named network declaration (so network exists before proxy/ai stacks start)
- `compose/ai/docker-compose.yml` — remove `litellm` service entirely; remove `depends_on: litellm` from Open WebUI; change `ai_internal` to `external: true`
- `compose/ai/litellm-config.yaml` — deleted (moved to proxy stack)
- `docs/runbooks/ai-stack.md` — updated topology, new startup order, stack separation
- `docs/ports.md` — reassign LiteLLM entry from `compose/ai/` to `compose/proxy/`

## Capabilities

### New Capabilities

- `litellm-proxy-standalone`: LiteLLM running as a standalone `compose/proxy/` stack, attached to both `traefik` and `ai_internal` external networks, routing to Ollama (and future llama.cpp) backends

### Modified Capabilities

- `litellm-proxy`: REMOVED from `compose/ai/`; superseded by `litellm-proxy-standalone`. Requirement for co-location with Ollama removed.
- `open-webui`: `depends_on: litellm` removed (cross-stack dependency); Open WebUI reaches LiteLLM via the shared `ai_internal` external network
- `traefik-core-proxy`: `ai_internal` named network added to core stack so it exists at platform startup

## Impact

- **Network change**: `ai_internal` moves from an implicitly-created `compose/ai/` local network to an explicitly-declared named Docker network created by `compose/core/`; all dependent stacks reference it as `external: true`
- **Startup order**: `compose/core/` → `compose/ai/` + `compose/proxy/` (parallel, both depend on core for networks); Open WebUI no longer has a cross-stack `depends_on`
- **Secrets**: new `secrets/proxy.enc.yaml` holds LiteLLM gateway credentials (`LITELLM_MASTER_KEY`, `LITELLM_SECRET_KEY`); `compose/proxy/` uses `/srv/platform/secrets/proxy.yaml`; `secrets/ai.enc.yaml` retains `LITELLM_MASTER_KEY` for Open WebUI's auth to LiteLLM
- **Coordinated migration**: Requires one down/up cycle for the ai stack to pick up the network change
- **Docs**: `docs/runbooks/ai-stack.md`, `docs/ports.md` updated to reflect new topology
