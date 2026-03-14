## ADDED Requirements

### Requirement: Prometheus runs as a Docker Compose service
The system SHALL deploy Prometheus as a Docker Compose service with a pinned image tag, named volume for data persistence, `observability_internal` network only, healthcheck, and `restart: unless-stopped`.

#### Scenario: Prometheus starts and is healthy
- **WHEN** the observability stack is brought up with `docker compose up -d`
- **THEN** the `prometheus` container reaches `healthy` status within 60 seconds

#### Scenario: Prometheus data persists across container recreation
- **WHEN** the `prometheus` container is recreated with `--force-recreate`
- **THEN** previously scraped metrics are still accessible after restart

### Requirement: Prometheus scrapes all platform targets
The system SHALL configure Prometheus scrape jobs for: Node Exporter (host metrics), cAdvisor (container metrics), the ROCm GPU exporter, Traefik (via `/metrics` endpoint), and Prometheus itself.

#### Scenario: All scrape targets are UP
- **WHEN** `curl http://localhost:9090/api/v1/targets` is queried
- **THEN** all configured targets show `health: "up"` with no `DOWN` targets

### Requirement: Prometheus port is not exposed to the host
The system SHALL bind Prometheus port 9090 only on the `observability_internal` network, not on `0.0.0.0`.

#### Scenario: Port 9090 not host-bound
- **WHEN** `ss -tlnp | grep 9090` is run on the host
- **THEN** no output is returned
