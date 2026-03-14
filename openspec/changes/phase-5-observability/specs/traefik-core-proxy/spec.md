## ADDED Requirements

### Requirement: Traefik exposes a Prometheus metrics endpoint
Traefik SHALL enable the Prometheus metrics provider (`entryPoint: metrics`, port 8082) in its static configuration. The metrics endpoint MUST be accessible only on the `observability_internal` network to allow Prometheus scraping. Port 8082 MUST NOT be bound on `0.0.0.0`.

#### Scenario: Prometheus scrapes Traefik metrics
- **WHEN** Prometheus has a scrape job targeting `traefik:8082/metrics`
- **THEN** `traefik_http_requests_total` and `traefik_http_request_duration_seconds` metrics are present in Prometheus

#### Scenario: Traefik metrics port not host-exposed
- **WHEN** `ss -tlnp | grep 8082` is run on the host
- **THEN** no output is returned
