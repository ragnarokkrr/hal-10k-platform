## ADDED Requirements

### Requirement: LiteLLM runs as an OpenAI-compatible proxy service
The system SHALL deploy LiteLLM in proxy mode as a Docker Compose service that routes requests to the Ollama backend and exposes an OpenAI-compatible REST API on port 4000.

#### Scenario: LiteLLM API is reachable on internal network
- **WHEN** `curl http://litellm:4000/health` is run from another container on `ai_internal`
- **THEN** response is HTTP 200

#### Scenario: Models endpoint lists available models
- **WHEN** `curl -H "Authorization: Bearer $LITELLM_MASTER_KEY" http://litellm:4000/models` is called
- **THEN** response includes model entries corresponding to the Ollama roster

### Requirement: LiteLLM is protected by master-key authentication
The LiteLLM proxy SHALL require a bearer token (master key) for all API requests. The master key SHALL be sourced from the decrypted `secrets/ai.enc.yaml` and injected as an environment variable.

#### Scenario: Request without auth token is rejected
- **WHEN** a request to `/v1/chat/completions` is made without an Authorization header
- **THEN** LiteLLM returns HTTP 401

#### Scenario: Request with correct master key succeeds
- **WHEN** a request includes `Authorization: Bearer <master-key>`
- **THEN** LiteLLM proxies the request to Ollama and returns a valid completion response

### Requirement: LiteLLM master key is never stored in plaintext in the repository
The LiteLLM master key SHALL reside only in `secrets/ai.enc.yaml` (SOPS-encrypted). The `.env` file SHALL be gitignored; only `.env.example` with placeholder values is committed.

#### Scenario: Repository contains no plaintext secrets
- **WHEN** `git grep -i "LITELLM_MASTER_KEY\s*=" -- ':!*.example'` is run
- **THEN** no matches are found

### Requirement: LiteLLM routes only to local Ollama
The LiteLLM configuration SHALL define only the local Ollama instance as a backend. No upstream cloud provider keys are required for initial deployment.

#### Scenario: Model routing targets Ollama
- **WHEN** a completion request is sent to LiteLLM
- **THEN** the request is forwarded to `http://ollama:11434` on the `ai_internal` network

### Requirement: LiteLLM port is not exposed directly to the host
LiteLLM SHALL NOT map port 4000 to `0.0.0.0` on the host. External access is via Traefik only.

#### Scenario: LiteLLM port not host-mapped
- **WHEN** `docker compose ps` is inspected
- **THEN** port 4000 is not mapped to the host interface

### Requirement: Healthcheck is defined
The LiteLLM service SHALL define a Docker healthcheck polling `/health`.

#### Scenario: Container reports healthy
- **WHEN** `docker inspect litellm` is run after startup
- **THEN** health status is `healthy`

### Requirement: Service restarts automatically
The LiteLLM service SHALL have `restart: unless-stopped`.

#### Scenario: Service recovers from restart
- **WHEN** the LiteLLM container exits unexpectedly
- **THEN** Docker restarts it automatically
