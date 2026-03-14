# ADR-0006: LLM Serving — Ollama + LiteLLM

**Date**: 2026-03-14
**Status**: Accepted

---

## Context

Phase 4 of the HAL-10k roadmap deploys a local LLM serving layer for personal and
agentic use. The platform is a single-node AMD RDNA 3.5 machine (40 CU iGPU, ROCm 7.2).
The requirements are:

- Serve large quantised models (≥32B parameters) using the AMD GPU
- Expose an **OpenAI-compatible API** so tools like Claude Code and Cline work
  without code changes
- Provide a **browser chat UI** for interactive use
- Keep auth simple: a single master key protecting all API access
- No multi-node clustering, no cloud routing (local-only for now)

---

## Decision

Deploy a three-container stack in `compose/ai/`:

| Layer | Component | Role |
|-------|-----------|------|
| Model runner | **Ollama** (ROCm image) | GPU inference, model storage, model management CLI |
| API proxy | **LiteLLM** (proxy mode) | OpenAI-compatible API, master-key auth, model routing |
| Chat UI | **Open WebUI** | Browser interface, connected to LiteLLM |

Traffic flow: **Client → Traefik → LiteLLM → Ollama** (API)
                **Browser → Traefik → Open WebUI → LiteLLM → Ollama** (chat)

---

## Rationale

### Ollama over alternatives

| Criterion | Ollama | vLLM | llama.cpp | LM Studio |
|-----------|--------|------|-----------|-----------|
| AMD ROCm Docker support | Official image | Experimental | Build-time | GUI-only |
| Model management CLI | Built-in (`pull/list/rm`) | None | None | GUI |
| REST API | Native | OpenAI-compat | Server mode | OpenAI-compat |
| RDNA 3.5 maturity | Good (`HSA_OVERRIDE_GFX_VERSION`) | Immature | Good via Vulkan | N/A |
| Container operational simplicity | High | Low | Medium | N/A |

vLLM is the preferred choice for multi-user, high-throughput deployments, but its AMD GPU
support at this scale requires more manual tuning and is less stable than Ollama.
llama.cpp and LM Studio are better suited to the Experimentation Layer (Distrobox).

### LiteLLM over direct Ollama exposure

Exposing Ollama directly would require every API client to use Ollama's native API
(not OpenAI's), provide no auth layer, and make future backend swaps (e.g., to vLLM)
require reconfiguring every client. LiteLLM solves all three: it translates the
OpenAI dialect to Ollama's API, enforces master-key auth, and abstracts the backend.

### Open WebUI connected to LiteLLM (not directly to Ollama)

Routing Open WebUI through LiteLLM means both browser and API clients share the same
auth/routing/observability surface. Model additions only need to be made once (in
`litellm-config.yaml`), and Phase 5 Grafana metrics will cover all LLM traffic in one
place.

---

## Consequences

- **Positive**: OpenAI-compatible API works out of the box with Claude Code, Cline, and
  any OpenAI SDK client.
- **Positive**: Model management (`ollama pull/rm`) is decoupled from client configuration.
- **Positive**: LiteLLM `config.yaml` is version-controlled (secrets excluded); adding a
  model is a one-line change + container restart.
- **Negative**: One extra network hop (LiteLLM ≈ 1 ms overhead) for all requests.
  Acceptable for interactive and agentic use; revisit if batch throughput becomes a concern.
- **Negative**: LiteLLM is a third-party dependency with its own release cadence; pin the
  image tag and review on upgrade.

---

## Alternatives Considered

| Option | Rejected Because |
|--------|-----------------|
| Expose Ollama directly | No auth, Ollama-native API (not OpenAI), harder client migration |
| vLLM with ROCm | AMD GPU support immature for RDNA 3.5; higher ops complexity |
| llama.cpp Docker | Best for Vulkan/CPU; less feature-rich API; better as Distrobox experiment |
| LM Studio | Desktop GUI only; not suitable for headless container deployment |
