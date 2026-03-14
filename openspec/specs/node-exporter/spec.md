## ADDED Requirements

### Requirement: Node Exporter runs as a Docker Compose service
The system SHALL deploy Node Exporter as a Docker Compose service with a pinned image tag, read-only bind mounts for host `/proc`, `/sys`, and `/`, `observability_internal` network only, `pid: host` mode, healthcheck, and `restart: unless-stopped`.

#### Scenario: Node Exporter starts and is healthy
- **WHEN** the observability stack is brought up
- **THEN** the `node-exporter` container reaches `healthy` status within 30 seconds

### Requirement: Node Exporter exposes host metrics to Prometheus
The system SHALL expose host CPU, RAM, disk I/O, filesystem usage, and network metrics at port 9100 on the `observability_internal` network, scraped by Prometheus.

#### Scenario: Host metrics available in Prometheus
- **WHEN** Prometheus has scraped Node Exporter at least once
- **THEN** `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, and `node_filesystem_avail_bytes` metrics are queryable in Grafana

### Requirement: Node Exporter port is not exposed to the host
The system SHALL bind Node Exporter port 9100 only on `observability_internal`, not on `0.0.0.0`.

#### Scenario: Port 9100 not host-bound
- **WHEN** `ss -tlnp | grep 9100` is run on the host
- **THEN** no output is returned
