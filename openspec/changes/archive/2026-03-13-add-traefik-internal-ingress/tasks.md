## 1. Network & Secrets Preparation

- [x] 1.1 Create `scripts/create-traefik-network.sh` — idempotent script that creates the `traefik` external Docker network
- [x] 1.2 Generate self-signed wildcard TLS certificate and key for `*.hal.local` (openssl command in runbook)
- [x] 1.3 Generate `htpasswd` hash for dashboard basic-auth credentials
- [x] 1.4 Create `secrets/core.enc.yaml` with SOPS + age containing: TLS cert, TLS key, dashboard `htpasswd` hash
- [x] 1.5 Create `compose/core/.env.example` documenting all required env vars (no secrets)

## 2. Traefik Static & Dynamic Configuration

- [x] 2.1 Create `compose/core/config/traefik.yml` — static config: entrypoints (web :80, websecure :443, dashboard :8080), Docker provider, `exposedByDefault: false`, log level
- [x] 2.2 Create `compose/core/config/dynamic/tls.yml` — dynamic config: TLS store referencing `*.hal.local` cert/key mounted from secrets
- [x] 2.3 Create `compose/core/config/dynamic/middlewares.yml` — `redirect-to-https` middleware (HTTP → HTTPS redirect) and `dashboard-auth` BasicAuth middleware

## 3. Compose Stack

- [x] 3.1 Create `compose/core/docker-compose.yml` with pinned `traefik:v3.3` image, port bindings (80, 443, 8080), volume mounts (static config, dynamic config, TLS certs, Docker socket), `env_file: /srv/platform/secrets/core.yaml`, `traefik` external network, healthcheck, and `restart: unless-stopped`

## 4. Documentation

- [x] 4.1 Create `docs/decisions/adr/ADR-0004-reverse-proxy-traefik.md` covering decision, rationale, and alternatives (Caddy, nginx-proxy)
- [x] 4.2 Create `docs/runbooks/core-traefik.md` covering prerequisites, deployment steps, verification commands, label convention for downstream stacks, and rollback
- [x] 4.3 Create `docs/ports.md` — authoritative port registry for the platform (all known service ports)
- [x] 4.4 Update `docs/architecture/platform-overview.md` network table to reflect Traefik as the ingress layer

## 5. Verification

- [x] 5.1 Run `scripts/create-traefik-network.sh` and confirm `docker network ls` shows `traefik`
- [x] 5.2 Decrypt secrets: `scripts/secrets-decrypt.sh core` and confirm `/srv/platform/secrets/core.yaml` is present
- [x] 5.3 `docker compose -f compose/core/docker-compose.yml up -d` — confirm container reaches healthy state
- [x] 5.4 Verify dashboard is reachable at `http://hal-10k.local:8080/dashboard/` with basic-auth
- [x] 5.5 Verify HTTP → HTTPS redirect works for a test router label on a dummy service
- [x] 5.6 Update `ROADMAP.md` Phase 3 checkboxes to mark completed items
