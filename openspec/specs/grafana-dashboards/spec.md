## ADDED Requirements

### Requirement: Grafana runs as a Docker Compose service
The system SHALL deploy Grafana as a Docker Compose service with a pinned image tag, named volume for state persistence, `observability_internal` + `proxy` networks, healthcheck, `restart: unless-stopped`, and admin credentials sourced from SOPS-encrypted secrets.

#### Scenario: Grafana starts and is healthy
- **WHEN** the observability stack is brought up
- **THEN** the `grafana` container reaches `healthy` status within 60 seconds

### Requirement: Grafana is accessible via Traefik HTTPS
The system SHALL configure Traefik labels on the Grafana service to route HTTPS traffic from `grafana.hal.local` to Grafana's port 3000.

#### Scenario: Grafana HTTPS access via Traefik
- **WHEN** `curl -sk -o /dev/null -w "%{http_code}\n" https://grafana.hal.local/` is run
- **THEN** the response is `200` or `302` (redirect to login)

### Requirement: Grafana provisioned datasources are configured on startup
The system SHALL provision Prometheus and Loki as Grafana datasources via repo-managed provisioning files, applied automatically on container start.

#### Scenario: Datasources present after fresh deploy
- **WHEN** Grafana starts for the first time
- **THEN** both `Prometheus` and `Loki` datasources appear in Grafana's datasource list without manual configuration

### Requirement: Foundation dashboards are provisioned on startup
The system SHALL provision the following Grafana dashboards from repo-managed JSON files: Host Overview (CPU, RAM, disk, network), GPU/ROCm (utilisation, VRAM, temperature, power), Container Resources (per-stack CPU/RAM via cAdvisor), Traefik (request rate, error rate, latency), Ollama Inference (request rate, latency), LiteLLM Proxy (token throughput, per-model routing).

#### Scenario: Dashboards visible after fresh deploy
- **WHEN** Grafana starts with provisioning config mounted
- **THEN** all six foundation dashboards appear in the Grafana UI without manual import

### Requirement: Grafana admin credentials are stored in SOPS-encrypted secrets
The system SHALL source `GF_SECURITY_ADMIN_PASSWORD` from `/srv/platform/secrets/observability.yaml`, decrypted from `secrets/observability.enc.yaml` via SOPS. Plaintext credentials MUST NOT appear in the repository.

#### Scenario: No plaintext credentials in repo
- **WHEN** `git grep -i "admin_password" -- ':!*.enc.yaml' ':!*.example'` is run
- **THEN** no matches are found
