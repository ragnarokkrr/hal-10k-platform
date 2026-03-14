## ADDED Requirements

### Requirement: Ollama runs as a GPU-accelerated Docker service
The system SHALL deploy Ollama as a Docker Compose service using the official ROCm-enabled image with AMD GPU device reservation and ROCm environment variables.

#### Scenario: Service starts with GPU access
- **WHEN** `docker compose up -d` is run in `compose/ai/`
- **THEN** Ollama container starts, logs show ROCm device detection, and `ollama list` returns without error

#### Scenario: GPU devices are passed through
- **WHEN** the Compose file is inspected
- **THEN** the Ollama service SHALL list `/dev/kfd` and `/dev/dri` under `devices`, and add `video` and `render` supplementary groups via `group_add`

### Requirement: Model weights stored at a well-known host path
The system SHALL bind-mount `/srv/platform/models/` into the Ollama container so model weights persist across container rebuilds.

#### Scenario: Models survive container recreation
- **WHEN** the Ollama container is removed and re-created
- **THEN** previously pulled models are still available via `ollama list`

#### Scenario: Bind-mount path is correct
- **WHEN** the Compose file is inspected
- **THEN** the Ollama service SHALL bind-mount `/srv/platform/models/` to `/root/.ollama/models`

### Requirement: Ollama exposes its API only on the internal network
The Ollama service SHALL NOT be bound to `0.0.0.0` on the host; it SHALL only be reachable on the `ai_internal` Docker network. The network SHALL NOT use `internal: true` — outbound internet access is required to pull models. Isolation is enforced by the absence of host port mappings.

#### Scenario: Ollama port is not exposed to host
- **WHEN** `docker compose ps` is inspected
- **THEN** port 11434 is not mapped to the host

### Requirement: Initial model roster is pulled and verified
The system SHALL have Qwen2.5-Coder-32B, DeepSeek-R1-32B, and Llama-3.3-70B-Instruct available in Ollama after initial provisioning.

#### Scenario: All roster models are present
- **WHEN** `docker exec ollama ollama list` is run after initial setup
- **THEN** output includes entries for `qwen2.5-coder:32b`, `deepseek-r1:32b`, and `llama3.3:70b`

### Requirement: Healthcheck is defined
The Ollama service SHALL define a Docker healthcheck that polls the `/api/tags` endpoint.

#### Scenario: Container is healthy after startup
- **WHEN** `docker inspect ollama` is run after the service has started
- **THEN** the health status is `healthy`

### Requirement: Service restarts automatically
The Ollama service SHALL have `restart: unless-stopped` so it recovers from host reboots and unexpected crashes.

#### Scenario: Service restarts after host reboot
- **WHEN** the host is rebooted
- **THEN** the Ollama container restarts automatically without manual intervention
