## Requirements

### Requirement: compose/ai-tools/ defines one llama.cpp service per model
The `compose/ai-tools/docker-compose.yml` SHALL define a separate service for each supported model (e.g., `llama-cpp-qwen32b`, `llama-cpp-deepseek32b`, `llama-cpp-llama70b`). Each service SHALL use the same base image, GPU passthrough, and `--jinja` flag, differing only in the model file path. A shared YAML anchor (`x-llama-base`) SHALL avoid duplicating common configuration.

#### Scenario: Multiple services are defined
- **WHEN** the Compose file is inspected
- **THEN** at least two llama-cpp services are defined, each with a unique container name and model path

#### Scenario: Operator selectively starts models
- **WHEN** `docker compose -f compose/ai-tools/docker-compose.yml up -d llama-cpp-qwen32b` is run
- **THEN** only the `llama-cpp-qwen32b` container starts; other llama-cpp services remain stopped

### Requirement: llama.cpp services run as GPU-accelerated Docker containers
Each llama.cpp service in `compose/ai-tools/` SHALL use the official ROCm-enabled image with AMD GPU device reservation and ROCm environment variables.

#### Scenario: Service starts with GPU access
- **WHEN** `docker compose -f compose/ai-tools/docker-compose.yml up -d llama-cpp-qwen32b` is run
- **THEN** the container starts, logs show ROCm device detection and model loading, and the `/health` endpoint returns HTTP 200

#### Scenario: GPU devices are passed through
- **WHEN** the Compose file is inspected
- **THEN** each llama-cpp service SHALL list `/dev/kfd` and `/dev/dri` under `devices`, set `HSA_OVERRIDE_GFX_VERSION=11.0.0`, and add `video` and `render` supplementary groups via `group_add`

### Requirement: llama.cpp serves models with function calling enabled
Each llama.cpp server SHALL start with the `--jinja` flag to enable Jinja2 chat template rendering. This enables OpenAI-compatible function/tool calling for models whose GGUF metadata includes tool-call formatting.

#### Scenario: Function calling returns tool_calls in response
- **WHEN** a POST request to a llama-cpp container's `/v1/chat/completions` includes a `tools` array with a function definition
- **THEN** the response contains a `tool_calls` array with the model's structured function call output

#### Scenario: Jinja flag is present in server command
- **WHEN** the Compose file is inspected
- **THEN** every llama-cpp service command includes `--jinja`

### Requirement: GGUF model weights stored at /srv/platform/models/gguf/
The system SHALL bind-mount `/srv/platform/models/gguf/` read-only into all llama-cpp containers. Each service references its specific model file via its hardcoded `--model` flag.

#### Scenario: Model file is accessible inside container
- **WHEN** `docker exec llama-cpp-qwen32b ls /models/` is run
- **THEN** the GGUF files are listed in the shared mount

#### Scenario: Models survive container recreation
- **WHEN** a llama-cpp container is removed and re-created
- **THEN** the previously downloaded GGUF model is still available at `/srv/platform/models/gguf/`

### Requirement: Initial GGUF model roster is downloaded and verified
The system SHALL have at minimum `qwen2.5-coder-32b-instruct-q4_k_m.gguf` downloaded to `/srv/platform/models/gguf/` after initial provisioning.

#### Scenario: Primary model is present
- **WHEN** `ls /srv/platform/models/gguf/` is run after initial setup
- **THEN** output includes `qwen2.5-coder-32b-instruct-q4_k_m.gguf`

### Requirement: llama.cpp ports are not exposed directly to the host
No llama-cpp service SHALL map port 8080 to `0.0.0.0` on the host. Access is via LiteLLM on the `ai_internal` network only.

#### Scenario: Port not host-mapped
- **WHEN** `docker compose -f compose/ai-tools/docker-compose.yml ps` is inspected
- **THEN** port 8080 is not mapped to a host interface for any llama-cpp container

### Requirement: llama.cpp containers attach only to ai_internal external network
The `compose/ai-tools/` stack SHALL declare `ai_internal` as an external network. No llama-cpp container SHALL join the `traefik` network — llama.cpp has no authentication layer and must not be directly routable from the LAN.

#### Scenario: Containers are on ai_internal network
- **WHEN** `docker network inspect ai_internal` is run
- **THEN** all running llama-cpp containers are listed as connected endpoints

#### Scenario: Containers are not on traefik network
- **WHEN** `docker network inspect traefik` is run
- **THEN** no llama-cpp container is listed as a connected endpoint

### Requirement: Healthcheck and restart policy are defined for each service
Each llama-cpp service SHALL define a Docker healthcheck that polls the `/health` endpoint and set `restart: unless-stopped`.

#### Scenario: Container reports healthy after startup
- **WHEN** `docker inspect llama-cpp-qwen32b` is run after model loading completes
- **THEN** health status is `healthy`

### Requirement: compose/ai-tools/.env.example is committed; .env is gitignored
A `.env.example` with the `LLAMACPP_IMAGE` placeholder SHALL be committed. The `.env` file SHALL be gitignored.

#### Scenario: .env.example tracked, .env absent
- **WHEN** `git ls-files compose/ai-tools/` is run
- **THEN** `.env.example` appears in the output and `.env` does not

### Requirement: compose/ai-tools/ is not auto-started
The `compose/ai-tools/` stack SHALL NOT be included in any automated startup sequence. It is brought up on demand by the operator for agentic work and stopped when done to release GPU resources.

#### Scenario: Stack not in default startup
- **WHEN** the platform startup runbook is reviewed
- **THEN** `compose/ai-tools/` is listed as optional with a note about GPU contention and selective service startup

### Requirement: llama.cpp containers attach to observability_internal for metrics scraping
Each llama.cpp service SHALL attach to both `ai_internal` (for LiteLLM routing) and `observability_internal` (for Prometheus scraping). The llama.cpp `/metrics` Prometheus endpoint SHALL be scraped by the existing observability stack. This follows the same dual-network pattern used by Grafana (joins `observability_internal` + `traefik`).

#### Scenario: Prometheus scrapes llama.cpp metrics
- **WHEN** a llama.cpp container is running and `docker exec prometheus wget -qO- http://llama-cpp-qwen32b:8080/metrics` is run
- **THEN** Prometheus-format metrics are returned including `llama_*` counters

#### Scenario: Containers are on observability_internal network
- **WHEN** `docker network inspect observability_internal` is run while a llama.cpp container is running
- **THEN** the container is listed as a connected endpoint

### Requirement: Container logs are shipped to Loki automatically
llama.cpp container logs (model loading progress, inference errors, GPU device detection) SHALL be captured and forwarded to Loki via the global Docker Loki log driver configured in `/etc/docker/daemon.json`. No per-service log driver configuration is required.

#### Scenario: Logs appear in Loki
- **WHEN** a llama.cpp container has been running and a Loki query for `{compose_service="llama-cpp-qwen32b"}` is run in Grafana
- **THEN** model loading and inference log lines are returned
