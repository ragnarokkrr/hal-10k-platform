## ADDED Requirements

### Requirement: cAdvisor runs as a Docker Compose service
The system SHALL deploy cAdvisor as a Docker Compose service with a pinned image tag, read-only bind mounts for `/`, `/var/run`, `/sys`, and `/srv/platform/docker` (Docker data-root), `observability_internal` network only, healthcheck, and `restart: unless-stopped`.

#### Scenario: cAdvisor starts and is healthy
- **WHEN** the observability stack is brought up
- **THEN** the `cadvisor` container reaches `healthy` status within 30 seconds

### Requirement: cAdvisor exposes per-container resource metrics to Prometheus
The system SHALL expose per-container CPU, memory, network I/O, and filesystem metrics at port 8080 on the `observability_internal` network, scraped by Prometheus.

#### Scenario: Container metrics available in Prometheus
- **WHEN** Prometheus has scraped cAdvisor at least once
- **THEN** `container_cpu_usage_seconds_total` and `container_memory_usage_bytes` metrics are queryable in Grafana, labelled by container name

### Requirement: cAdvisor port is not exposed to the host
The system SHALL bind cAdvisor port 8080 only on `observability_internal`, not on `0.0.0.0`.

#### Scenario: Port 8080 not host-bound
- **WHEN** `ss -tlnp | grep 8080` is run on the host
- **THEN** no output is returned
