## ADDED Requirements

### Requirement: Traefik v3 reverse proxy deployed as core stack
The platform SHALL deploy Traefik v3 via `compose/core/docker-compose.yml` as the single entry point for all HTTP/HTTPS traffic on the HAL-10k host. The image tag MUST be pinned (e.g., `traefik:v3.3`). The container MUST define a healthcheck, a restart policy of `unless-stopped`, and named volumes for configuration and certificates.

#### Scenario: Core stack starts successfully
- **WHEN** `docker compose -f compose/core/docker-compose.yml up -d` is run with the `traefik` network present and `secrets/core.yaml` decrypted
- **THEN** the Traefik container reaches a healthy state and listens on host ports 80, 443, and 8080

#### Scenario: Traefik survives host reboot
- **WHEN** the host OS reboots
- **THEN** Docker starts the Traefik container automatically due to `restart: unless-stopped`

### Requirement: Shared `traefik` Docker network
The platform SHALL provide an external Docker network named `traefik`. All services requiring ingress routing MUST attach to this network. The network MUST be created before any dependent stack starts.

#### Scenario: Network creation is idempotent
- **WHEN** `scripts/create-traefik-network.sh` is run more than once
- **THEN** the script exits 0 without error and the network exists exactly once

#### Scenario: Downstream stack attaches to traefik network
- **WHEN** a service declares `networks: [traefik]` and the external network exists
- **THEN** Traefik can route traffic to that service via its Docker label configuration

### Requirement: Hostname-based routing via Docker labels
Traefik SHALL route incoming requests to services using the `Host()` rule defined in Docker labels on each service container. The naming convention SHALL be `<service>.hal.local`.

#### Scenario: Routing to a labeled service
- **WHEN** a container has label `traefik.http.routers.<name>.rule=Host('<service>.hal.local')` and is running
- **THEN** an HTTP request to `http://<service>.hal.local` is proxied to that container on its configured port

#### Scenario: Unlabeled container is not routed
- **WHEN** a container has no Traefik labels and `exposedByDefault: false` is set in static config
- **THEN** Traefik does not create a router for that container

### Requirement: HTTPS with self-signed wildcard TLS certificate
Traefik SHALL terminate TLS on port 443 using a self-signed wildcard certificate for `*.hal.local`. The certificate and private key SHALL be stored in `secrets/core.enc.yaml` (SOPS-encrypted) and mounted into the container at runtime. All routers targeting HTTPS MUST reference the `hal-local-tls` TLS store entry.

#### Scenario: HTTPS request is served
- **WHEN** a client sends an HTTPS request to `https://<service>.hal.local`
- **THEN** Traefik terminates TLS with the wildcard cert and proxies the request to the backend

#### Scenario: HTTP redirects to HTTPS
- **WHEN** a client sends an HTTP request on port 80
- **THEN** Traefik returns a 301/302 redirect to the HTTPS equivalent URL

### Requirement: Dashboard secured with basic-auth
The Traefik dashboard SHALL be accessible at `http://hal-10k.local:8080` and MUST be protected by HTTP basic authentication. The `htpasswd`-hashed credentials SHALL be stored in `secrets/core.enc.yaml` and injected via environment variable. Unauthenticated requests MUST receive a 401 response.

#### Scenario: Authenticated dashboard access
- **WHEN** a user provides valid basic-auth credentials at `http://hal-10k.local:8080/dashboard/`
- **THEN** the Traefik dashboard HTML is returned with status 200

#### Scenario: Unauthenticated access is rejected
- **WHEN** a request to the dashboard is made without credentials or with wrong credentials
- **THEN** Traefik returns HTTP 401 and the dashboard content is not served

### Requirement: Secrets managed via SOPS + age
All sensitive values (TLS certificate, private key, dashboard basic-auth hash) SHALL be stored in `secrets/core.enc.yaml` encrypted with SOPS + age. The decrypted file at `/srv/platform/secrets/core.yaml` SHALL be consumed by the Compose stack via `env_file`. No plaintext secrets SHALL appear in any committed file.

#### Scenario: Stack start with decrypted secrets
- **WHEN** `secrets/core.yaml` exists (decrypted) and `docker compose up -d` is run
- **THEN** Traefik loads TLS cert/key and dashboard auth from environment variables without error

#### Scenario: Missing secrets file causes startup failure
- **WHEN** `secrets/core.yaml` does not exist and `docker compose up -d` is run
- **THEN** Docker Compose returns a non-zero exit code indicating the env_file is missing

### Requirement: Operational runbook and ADR
The platform SHALL include `docs/runbooks/core-traefik.md` (step-numbered operational runbook) and `docs/decisions/adr/ADR-0002-reverse-proxy-traefik.md` (architectural decision record). These documents MUST be created or updated as part of this change.

#### Scenario: Runbook covers full lifecycle
- **WHEN** an operator follows `docs/runbooks/core-traefik.md`
- **THEN** they can deploy, verify, update, and roll back the Traefik stack without additional guidance

#### Scenario: ADR records the decision
- **WHEN** a new team member reads `ADR-0002`
- **THEN** they understand why Traefik was chosen over Caddy or nginx-proxy with alternatives documented
