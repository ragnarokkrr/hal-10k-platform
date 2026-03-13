## Context

HAL-10k currently has no unified ingress. Each service is accessed by `hal-10k.local:<port>`, which is hard to remember, lacks TLS, and provides no central access control. Phase 3 of the roadmap designates Traefik v3 as the reverse proxy. It will run as the `core` Compose stack — the first stack up and last stack down — and all platform stacks will share a single `traefik` Docker network.

## Goals / Non-Goals

**Goals:**

- Single HTTP/HTTPS entry point on ports 80 and 443 (LAN only)
- Hostname-based routing via Docker label autodiscovery (`*.hal.local`)
- Traefik v3 dashboard secured with basic-auth, accessible on port 8080 (LAN only)
- TLS via self-signed wildcard cert (initially); Let's Encrypt ACME optional future path
- Dashboard credentials managed via SOPS-encrypted `secrets/core.enc.yaml`
- Shared `traefik` external Docker network so stacks remain independently deployable

**Non-Goals:**

- Internet-facing TLS / Let's Encrypt in this phase
- mTLS between services (planned for a later security hardening phase)
- Rate limiting or WAF features
- Kubernetes IngressRoute CRDs

## Decisions

### D1 — Traefik v3 over Caddy or nginx-proxy

Traefik v3 is chosen because it has native Docker label autodiscovery (no reload on config change), a built-in dashboard for visibility, and first-class Compose integration. Caddy is simpler but lacks dynamic Docker discovery without plugins. nginx-proxy requires manual upstream management.

### D2 — Shared `traefik` external network

Rather than embedding Traefik in every stack's network, a single named external network (`traefik`) is created once. Each stack declares it as external and attaches containers that need routing. This decouples stacks — they can be brought up/down independently without breaking the proxy.

**Alternative considered**: One network per stack joined by Traefik — rejected because Traefik would need to be restarted each time a new stack network appeared.

### D3 — TLS with self-signed wildcard cert (Phase 3)

A wildcard certificate for `*.hal.local` is generated via `openssl` and mounted into Traefik. Let's Encrypt ACME (with DNS challenge) is deferred to Phase 3.5 or later because HAL-10k is LAN-only and a public DNS challenge is not straightforward. The cert and key are stored as SOPS secrets.

### D4 — Dashboard basic-auth via middleware

The Traefik dashboard is exposed on `:8080` with a `BasicAuth` middleware. Credentials (`htpasswd` hash) are injected via environment variable from `secrets/core.yaml` and referenced in static config. This avoids storing plaintext passwords in compose files.

### D5 — Static config via file (not CLI flags)

Traefik static config (`traefik.yml`) is mounted as a volume. This is more maintainable and review-friendly than a long `command:` array. Dynamic config (TLS stores, middlewares) is also file-based.

## Risks / Trade-offs

| Risk | Mitigation |
|------|-----------|
| Self-signed cert causes browser warnings | Document cert import in LAN devices; warn in runbook |
| `traefik` network must exist before any dependent stack starts | Add `create-traefik-network.sh` idempotent helper; document in runbook |
| Dashboard exposed on `:8080` without TLS | Bind to LAN interface only; basic-auth required; document in runbook |
| Traefik v3 label syntax differs from v2 | Use v3-only labels throughout; pin `traefik:v3.x` image |
| Stale routing if a container stops but its label persists | Traefik watches Docker events; dead containers are removed automatically |

## Migration Plan

1. Create `traefik` Docker network (idempotent script)
2. Decrypt `secrets/core.enc.yaml` → `/srv/platform/secrets/core.yaml`
3. `docker compose -f compose/core/docker-compose.yml up -d`
4. Verify dashboard at `http://hal-10k.local:8080`
5. When adding a new stack: attach to `traefik` network and add labels

**Rollback**: `docker compose -f compose/core/docker-compose.yml down` — all other stacks fall back to direct port access.

## Open Questions

- Domain convention: `<service>.hal.local` or `hal-10k.local/<service>`? → Hostname-based (`<service>.hal.local`) preferred for clean TLS wildcard coverage.
- Let's Encrypt timeline: deferred until Gitea is live (Phase 7) and a DNS provider is in place.
