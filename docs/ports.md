# HAL-10k Platform — Port Registry

Authoritative list of all ports used by platform services.
Update this file whenever a new service is added or a port changes.

---

## Ingress (host-bound, LAN-accessible)

| Port | Protocol | Service | Stack | Notes |
|------|----------|---------|-------|-------|
| 80   | TCP | Traefik HTTP | `compose/core` | Redirects to 443 via `redirect-to-https` middleware |
| 443  | TCP | Traefik HTTPS | `compose/core` | TLS termination; wildcard `*.hal.local` cert |
| 8080 | TCP | Traefik Dashboard | `compose/core` | Basic-auth protected; LAN only |
| 9443 | TCP | Portainer | bootstrap | HTTPS; container management UI |
| 5001 | TCP | Dockge | bootstrap | Stack management UI |
| 3389 | TCP | XRDP | bootstrap | Remote desktop (LAN only) |

---

## Service Layer (internal + Traefik-routed)

| Port | Protocol | Service | Stack | Hostname | Access |
|------|----------|---------|-------|----------|--------|
| 3000 | TCP | Open WebUI | `compose/ai` | `openwebui.hal.local` | Via Traefik |
| 4000 | TCP | LiteLLM Proxy | `compose/proxy` | `litellm.hal.local` | Via Traefik |
| 11434 | TCP | Ollama | `compose/ai` | — | Internal only |
| 3000 | TCP | Grafana | `compose/observability` | `grafana.hal.local` | Via Traefik |
| 9090 | TCP | Prometheus | `compose/observability` | — | Internal only |
| 3100 | TCP | Loki | `compose/observability` | — | Internal only (+ host log driver push) |
| 9100 | TCP | Node Exporter | `compose/observability` | — | Internal only |
| 8080 | TCP | cAdvisor | `compose/observability` | — | Internal only |
| 8082 | TCP | Traefik metrics | `compose/core` | — | Internal only (Prometheus scrape) |
| 5678 | TCP | n8n | `compose/workflows` | `n8n.hal.local` | Via Traefik |
| 8000 | TCP | ChromaDB | `compose/data` | — | Internal only |
| 3001 | TCP | Gitea | `compose/gitea` | `gitea.hal.local` | Via Traefik |

---

## Notes

- **Internal only**: service is not exposed on the host; accessible only to containers
  on the same Docker network.
- **Via Traefik**: service is accessed via `https://<hostname>.hal.local` through the
  Traefik reverse proxy on port 443. Direct port access on the host is not bound.
- Ports 80 and 443 are reserved exclusively for Traefik. No other service may bind them.
- All Traefik-routed services must attach to the `traefik` external Docker network and
  carry `traefik.enable=true` plus routing labels (see
  [runbooks/core-traefik.md](runbooks/core-traefik.md)).
