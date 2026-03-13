# ADR-0005: Docker Socket Proxy for Traefik Label Discovery

**Date**: 2026-03-13
**Status**: Accepted

---

## Context

Traefik's Docker provider requires access to the Docker daemon to watch container events
and read labels for service autodiscovery. The conventional approach is to bind-mount
`/var/run/docker.sock` directly into the Traefik container.

During deployment on HAL-10k (Docker CE 29.3.0, API 1.54, minimum enforced API 1.40),
Traefik v3.3 failed to connect to the Docker provider with:

```
Error response from daemon: client version 1.24 is too old.
Minimum supported API version is 1.40, please upgrade your client to a newer version
```

**Root cause**: Traefik's embedded Docker SDK client calls `WithAPIVersionNegotiation()`.
The negotiation handshake opens with the SDK's default version (1.24) in the request
path (`GET /v1.24/version`). Docker CE 29 enforces a minimum API version of 1.40 and
returns HTTP 400 for any request using a path below `/v1.40/`, aborting the handshake
before negotiation can complete.

`tecnativa/docker-socket-proxy` was evaluated first but found to be a transparent
allowlist proxy — it forwards the `/v1.24/` path unchanged to the daemon, which still
rejects it. API version rewriting is required.

## Decision

Deploy an **nginx-based Docker socket proxy** as a companion service in `compose/core`.

The proxy (`nginx:1.27-alpine`) with a custom `config/docker-proxy/nginx.conf`:

- Listens on `tcp://docker-socket-proxy:2375` inside the `proxy-socket` internal Docker
  network
- **Rewrites any versioned API path** `/vX.YY/...` → `/v1.45/...` before forwarding to
  `/var/run/docker.sock`
- This makes Traefik's `/v1.24/version` call reach the daemon as `/v1.45/version`,
  which Docker CE 29 accepts (1.45 is within its supported 1.40–1.54 range)
- After successful negotiation, Traefik stores the daemon's reported API version (1.54)
  and uses it for subsequent calls — those are also rewritten to 1.45, which the daemon
  still handles correctly

Traefik's static config points to the proxy:

```yaml
providers:
  docker:
    endpoint: "tcp://docker-socket-proxy:2375"
```

The raw Docker socket volume mount is removed from the Traefik service.

## Rationale

### Solves the API version mismatch without changing the Traefik image

Rewriting the URL path before it reaches the daemon is the only reliable fix given
that Traefik's `WithAPIVersionNegotiation()` ignores `DOCKER_API_VERSION` env vars and
there is no provider-level API version setting in Traefik's static config.

### Reduces attack surface (security improvement)

Mounting `/var/run/docker.sock` directly into a container grants full Docker API
access — equivalent to root on the host. If Traefik were compromised, an attacker could
start, stop, or modify any container.

The nginx proxy sits between Traefik and the socket. Future hardening can add nginx
`allow`/`deny` location rules to restrict which Docker API endpoints are reachable
(e.g., allow only `GET /v*/containers/json` and `GET /v*/networks`).

### Minimal complexity

`nginx:alpine` is a well-understood, stable base. The custom config is a single
`nginx.conf` file committed alongside the compose stack. No custom Dockerfile is needed.
The `proxy-socket` network is `internal: true` — not reachable from the host or the
`traefik` routing network.

## Consequences

**Positive**:
- Traefik Docker provider connects successfully on Docker CE 29+
- No Traefik image change; `traefik:v3.3` pinned as specified
- The proxy is version-agnostic — will continue to work as Docker API versions advance
- `proxy-socket` is isolated from all other networks

**Negative / Trade-offs**:
- One additional container to operate and keep updated (`nginx:1.27-alpine`)
- The nginx proxy does not yet enforce an API endpoint allowlist (future hardening task)
- All Docker API paths are rewritten to v1.45 — if the daemon ever drops support for
  1.45, the pinned version in `nginx.conf` must be updated

## Alternatives Rejected

- **`DOCKER_API_VERSION` env var**: Set to `1.45` in the Traefik container but did not
  prevent the 1.24 handshake. Traefik's `WithAPIVersionNegotiation()` overrides it.
- **`tecnativa/docker-socket-proxy`**: Transparent allowlist proxy — passes `/v1.24/`
  unchanged to the daemon, which still rejects it.
- **Traefik `latest` tag**: May use a newer SDK but violates the pin-to-tag spec
  requirement for production stability.
- **Docker CE downgrade**: Destructive; removes security and feature updates.
- **Wait for upstream fix**: Valid long-term path, but Traefik v3.3.7 has not addressed
  this as of 2026-03-13. This proxy is version-agnostic and can be removed if/when
  Traefik upgrades its Docker SDK default.
