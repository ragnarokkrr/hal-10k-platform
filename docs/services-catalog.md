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

## Observability Stack (`compose/observability/`)

| Service | Image | Internal Port | Network(s) | Volume(s) | Purpose |
|---------|-------|---------------|------------|-----------|---------|
| `prometheus` | `prom/prometheus:v3.2.1` | 9090 | `observability_internal` | `prometheus_data` (30d retention) | Metrics collection & alerting |
| `loki` | `grafana/loki:3.4.2` | 3100 | `observability_internal` | `loki_data` (30d retention) | Log aggregation backend |
| `grafana` | `grafana/grafana:11.6.0` | 3000 | `observability_internal`, `traefik` | `grafana_data` | Dashboards & visualisation |
| `node-exporter` | `prom/node-exporter:v1.9.1` | 9100 | `observability_internal` | `/proc`, `/sys`, `/` (ro bind) | Host-level metrics (CPU, RAM, disk, network) |
| `cadvisor` | `gcr.io/cadvisor/cadvisor:v0.52.0` | 8080 | `observability_internal` | `/`, `/sys`, `/var/lib/docker` (ro) | Per-container resource metrics |

**Traefik hostname**: Grafana → `https://grafana.hal.local`

**Secrets**: `secrets/observability.enc.yaml` (SOPS) — decrypted at runtime to `/srv/platform/secrets/observability.yaml`

**Note**: cAdvisor per-container labelling is limited with Docker 29+ containerd snapshotter. Host metrics from node-exporter are fully operational. See [runbooks/observability.md](runbooks/observability.md#5-known-limitations).

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
| `compose/data/` | ChromaDB | Phase 7 |
| `compose/workflows/` | n8n | Phase 8 |
| `compose/gitea/` | Gitea + PostgreSQL | Phase 9 |

---

## Networks

| Network | Type | Used By |
|---------|------|---------|
| `traefik` | External bridge | All Traefik-routed services |
| `proxy-socket` | Internal bridge | Traefik ↔ docker-socket-proxy |
| `ai_internal` | Internal bridge | Ollama ↔ LiteLLM ↔ Open WebUI |
| `observability_internal` | Bridge | Prometheus ↔ Grafana ↔ Loki ↔ exporters; Traefik scrape target |

---

## Volumes

| Volume | Stack | Contents |
|--------|-------|---------|
| `/srv/platform/models/` (bind) | AI | Ollama model weights |
| `open_webui_data` (named) | AI | Open WebUI user data, chat history, RAG docs |
| `prometheus_data` (named) | Observability | Prometheus TSDB — 30-day retention |
| `grafana_data` (named) | Observability | Grafana user accounts, dashboard edits, alert rules |
| `loki_data` (named) | Observability | Loki log chunks and index — 30-day retention |
