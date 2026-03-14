## ADDED Requirements

### Requirement: Loki runs as a Docker Compose service
The system SHALL deploy Loki as a Docker Compose service with a pinned image tag, named volume for log persistence, `observability_internal` network only, healthcheck, and `restart: unless-stopped`.

#### Scenario: Loki starts and is healthy
- **WHEN** the observability stack is brought up
- **THEN** the `loki` container reaches `healthy` status within 60 seconds

### Requirement: Docker Loki log driver ships logs from all stacks
The system SHALL configure the Docker daemon (`/etc/docker/daemon.json`) with the Loki log driver as the default logging driver, pointing to `http://localhost:3100`. All containers started after this change SHALL have their logs shipped to Loki automatically.

#### Scenario: Container logs appear in Loki
- **WHEN** a container from the core or ai stack is running and produces log output
- **THEN** querying Loki via `{container_name="traefik"}` in Grafana returns log lines

### Requirement: Loki port is not exposed to the host
The system SHALL bind Loki port 3100 only on the `observability_internal` network, not on `0.0.0.0`.

#### Scenario: Port 3100 not host-bound
- **WHEN** `ss -tlnp | grep 3100` is run on the host
- **THEN** no output is returned

### Requirement: Log retention policy is configured
The system SHALL configure Loki with a retention period of at least 30 days and a maximum storage limit appropriate for the available disk space on `/srv/platform`.

#### Scenario: Retention config present
- **WHEN** the Loki config file is inspected
- **THEN** `retention_period` is set and `retention_enabled: true`
