# HAL-10k Platform — Services Catalog

Authoritative registry of all platform services.
Update this file when adding, removing, or changing a service.

---

## Core Stack (`compose/core/`)

| Service | Image | Internal Port | Network(s) | Volume(s) | Purpose |
|---------|-------|---------------|------------|-----------|---------|
| `traefik` | `traefik:v3.3` | 80, 443, 8080 | `traefik`, `proxy-socket` | — | Reverse proxy, TLS termination, HTTP→HTTPS redirect |
| `docker-socket-proxy` | `nginx:1.27-alpine` | 2375 | `proxy-socket` | `/var/run/docker.sock` (ro) | Restricts Traefik's Docker socket access (ADR-0005) |

---

## AI Stack (`compose/ai/`)

| Service | Image | Internal Port | Network(s) | Volume(s) | Purpose |
|---------|-------|---------------|------------|-----------|---------|
| `ollama` | `ollama/ollama:<ver>-rocm` | 11434 | `ai_internal` | `/srv/platform/models` (bind) | GPU-accelerated LLM inference (ROCm / AMD RDNA 3.5) |
| `litellm` | `ghcr.io/berriai/litellm:<ver>` | 4000 | `ai_internal`, `traefik` | `./litellm-config.yaml` (ro) | OpenAI-compatible API proxy, master-key auth; routes to Ollama |
| `open-webui` | `ghcr.io/open-webui/open-webui:<ver>` | 8080 | `ai_internal`, `traefik` | `open_webui_data` (named) | Browser-based chat UI; calls LiteLLM backend |

**Traefik hostnames**:
- Open WebUI → `https://openwebui.hal.local`
- LiteLLM API → `https://litellm.hal.local`

**Secrets**: `secrets/ai.enc.yaml` (SOPS) — decrypted at runtime to `/srv/platform/secrets/ai.yaml`

---

## Bootstrap Services (not Compose-managed)

| Service | Access | Purpose |
|---------|--------|---------|
| Portainer | `https://hal-10k.local:9443` | Container management UI |
| Dockge | `http://hal-10k.local:5001` | Compose stack management UI |
| XRDP | `hal-10k.local:3389` | Remote desktop (LAN only) |

---

## Planned Services

| Stack | Service | Phase |
|-------|---------|-------|
| `compose/observability/` | Prometheus + Grafana + Loki | Phase 5 |
| `compose/data/` | ChromaDB | Phase 6 |
| `compose/workflows/` | n8n | Phase 7 |
| `compose/gitea/` | Gitea + PostgreSQL | Phase 8 |

---

## Networks

| Network | Type | Used By |
|---------|------|---------|
| `traefik` | External bridge | All Traefik-routed services |
| `proxy-socket` | Internal bridge | Traefik ↔ docker-socket-proxy |
| `ai_internal` | Internal bridge | Ollama ↔ LiteLLM ↔ Open WebUI |

---

## Volumes

| Volume | Stack | Contents |
|--------|-------|---------|
| `/srv/platform/models/` (bind) | AI | Ollama model weights |
| `open_webui_data` (named) | AI | Open WebUI user data, chat history, RAG docs |
