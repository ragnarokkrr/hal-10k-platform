## ADDED Requirements

### Requirement: LiteLLM runs as a standalone proxy stack in compose/proxy/
The system SHALL deploy LiteLLM as the sole service in `compose/proxy/docker-compose.yml`, not co-located with Ollama or Open WebUI.

#### Scenario: LiteLLM container is in its own compose project
- **WHEN** `docker compose -f compose/proxy/docker-compose.yml ps` is run
- **THEN** only the litellm service is listed

### Requirement: LiteLLM attaches to both traefik and ai_internal external networks
The proxy stack SHALL declare both `traefik` and `ai_internal` as external networks with `name:` overrides. LiteLLM SHALL be attached to both.

#### Scenario: LiteLLM is on ai_internal network
- **WHEN** `docker network inspect ai_internal` is run
- **THEN** the litellm container is listed as a connected endpoint

#### Scenario: LiteLLM is on traefik network
- **WHEN** `docker network inspect traefik` is run
- **THEN** the litellm container is listed as a connected endpoint

### Requirement: LiteLLM config routes to Ollama via ai_internal
The `litellm-config.yaml` in `compose/proxy/` SHALL set `api_base` to `http://ollama:11434/v1` for all Ollama-backed models. The Ollama container is reachable by this hostname via the shared `ai_internal` network.

#### Scenario: Model completion routes to Ollama
- **WHEN** a chat completion request is sent to `https://litellm.hal.local/v1/chat/completions` with a valid model name
- **THEN** the request is forwarded to Ollama on the ai_internal network and a valid response is returned

### Requirement: compose/proxy/.env.example is committed; .env is gitignored
A `.env.example` with the `LITELLM_IMAGE` placeholder SHALL be committed. The `.env` file SHALL be gitignored.

#### Scenario: .env.example tracked, .env absent
- **WHEN** `git ls-files compose/proxy/` is run
- **THEN** `.env.example` appears in the output and `.env` does not

### Requirement: LiteLLM port is not exposed directly to the host
LiteLLM SHALL NOT map port 4000 to `0.0.0.0` on the host. External access is via Traefik only.

#### Scenario: Port not host-mapped
- **WHEN** `docker compose -f compose/proxy/docker-compose.yml ps` is inspected
- **THEN** port 4000 is not mapped to a host interface

### Requirement: Healthcheck and restart policy are defined
The LiteLLM service SHALL define a Docker healthcheck and `restart: unless-stopped`.

#### Scenario: Container reports healthy after startup
- **WHEN** `docker inspect litellm` is run after startup
- **THEN** health status is `healthy`
