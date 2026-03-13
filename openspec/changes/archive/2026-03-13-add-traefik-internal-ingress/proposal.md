## Why

The HAL-10k platform has multiple services running on distinct ports with no unified entry point, TLS termination, or hostname-based routing. Traefik v3 fulfils Phase 3 of the roadmap by providing a single reverse proxy that routes all LAN traffic by hostname, terminates TLS, and enables clean per-service URLs without port numbers.

## What Changes

- New `compose/core/` Compose stack deploying Traefik v3 on ports 80, 443, and 8080 (dashboard)
- Traefik dashboard secured with basic-auth via SOPS-encrypted credentials
- `traefik` external Docker network created and shared by all stacks
- `compose/core/.env.example` documenting required env vars
- `secrets/core.enc.yaml` storing TLS and dashboard credentials (SOPS + age)
- All future stacks (ai, data, workflows) must attach to the `traefik` network and carry Traefik labels
- `docs/runbooks/core-traefik.md` — operational runbook
- `docs/decisions/adr/ADR-0004-reverse-proxy-traefik.md` — architectural decision record

## Capabilities

### New Capabilities

- `traefik-core-proxy`: Traefik v3 reverse proxy — HTTP/HTTPS ingress, hostname-based routing via Docker labels, dashboard with basic-auth, shared `traefik` Docker network for all platform stacks

### Modified Capabilities

<!-- No existing spec-level requirements are changing; all platform services are new. -->

## Impact

- All downstream stacks (ai, data, workflows, gitea) must join the `traefik` Docker network and add Traefik router/service labels
- `secrets/core.enc.yaml` must be decrypted to `/srv/platform/secrets/core.yaml` before stack start
- `compose/core/` is the first stack to bring up and the last to bring down
- Ports 80 and 443 are bound on the host; no other service may bind those ports
- `docs/architecture/platform-overview.md` network table and `docs/ports.md` (to be created) must be updated
