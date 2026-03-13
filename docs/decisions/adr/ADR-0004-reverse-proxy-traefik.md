# ADR-0004: Reverse Proxy — Traefik v3

**Date**: 2026-03-13
**Status**: Accepted

---

## Context

The HAL-10k platform runs multiple containerised services (Ollama, LiteLLM, Open WebUI,
n8n, Gitea, ChromaDB, Portainer, Dockge). Without a unified ingress layer each service
is accessed by `hal-10k.local:<port>`, which:

- Requires remembering non-standard port numbers
- Provides no TLS — traffic is plaintext on the LAN
- Offers no central access control or routing policy
- Becomes harder to manage as the number of services grows

Phase 3 of the roadmap specifies deploying a reverse proxy as the single entry point for
all HTTP/HTTPS traffic on the platform.

## Decision

Deploy **Traefik v3** as the `compose/core` stack — the first stack up and last stack
down. All platform services that require external access attach to a shared `traefik`
external Docker network and declare their routing rules via Docker labels.

## Rationale

| Criterion | Traefik v3 | Caddy | nginx-proxy |
|-----------|-----------|-------|-------------|
| Docker label autodiscovery | Native, no reload | Plugin only | nginx-proxy-manager only |
| Built-in dashboard | Yes | No | No |
| Let's Encrypt (future) | Native ACME | Native | Via companion container |
| Config complexity | Low (labels + YAML) | Low (Caddyfile) | Medium |
| v3 API maturity | Stable | Stable | Stable |
| Self-hosted LAN TLS | File-based cert mount | File-based cert mount | Manual |

Traefik's native Docker provider watches the Docker daemon for label changes in real time
— no reload or restart is needed when a new service starts. This is the decisive advantage
on a platform where stacks are deployed and torn down independently.

Caddy is simpler but its Docker integration requires a plugin
(`caddy-docker-proxy`) that adds an extra dependency and has its own update cadence.

nginx-proxy requires a companion container and manual upstream management; it was designed
for simpler multi-container scenarios and does not scale as cleanly to label-driven routing.

## Implementation

- Image pinned to `traefik:v3.3`
- Static config loaded from `compose/core/config/traefik.yml` (not CLI flags — easier to
  review and diff)
- Dynamic config (TLS store, middlewares) loaded from `compose/core/config/dynamic/`
  via file provider with `watch: true` (hot-reload without container restart)
- Shared external Docker network `traefik` created once with
  `scripts/create-traefik-network.sh`; stacks declare `networks: [traefik]` as external
- Self-signed wildcard cert for `*.hal.local` (Let's Encrypt ACME deferred to a later
  phase when a public DNS provider is in place)
- Dashboard on `:8080` behind `BasicAuth` middleware; credentials stored in
  `secrets/core.enc.yaml` (SOPS + age)

## Consequences

**Positive**:
- Single TLS termination point; all downstream stacks get HTTPS for free via labels
- Adding a new service only requires attaching it to the `traefik` network and adding
  three labels — no proxy config changes
- Dashboard provides real-time visibility into registered routers and services
- Stacks remain independently deployable; Traefik does not need to restart when stacks
  change

**Negative / Trade-offs**:
- Traefik is now a single point of failure for all HTTP/HTTPS ingress; if it is down,
  services are inaccessible via hostname (direct port access still works as fallback)
- Self-signed cert causes browser trust warnings on first access; operators must import
  the cert into their browser or LAN device trust store
- Docker socket is mounted read-only into Traefik; this is a known privilege trade-off
  — mitigated by using `:ro` and running on a LAN-only host

## Alternatives Rejected

- **Caddy with caddy-docker-proxy plugin**: Simpler Caddyfile syntax but adds a
  third-party plugin dependency for Docker autodiscovery; less battle-tested at this scale.
- **nginx-proxy + nginx-proxy-manager**: Requires a companion container and a separate
  management UI; does not support label-driven routing natively.
- **No proxy (direct port access)**: Current state — not viable long-term as service
  count grows and TLS becomes a requirement.
