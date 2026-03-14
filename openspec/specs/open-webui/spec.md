## ADDED Requirements

### Requirement: Open WebUI runs as a Docker Compose service connected to LiteLLM
The system SHALL deploy Open WebUI configured to use LiteLLM as its OpenAI API backend, enabling browser-based chat with all models in the LiteLLM roster.

#### Scenario: Open WebUI connects to LiteLLM on startup
- **WHEN** the Open WebUI container starts
- **THEN** its `OPENAI_API_BASE_URL` points to `http://litellm:4000/v1` and the API key matches `LITELLM_MASTER_KEY`

#### Scenario: Models are visible in the WebUI
- **WHEN** a user opens the model selector in the Open WebUI browser interface
- **THEN** all models registered in LiteLLM (Qwen2.5-Coder-32B, DeepSeek-R1-32B, Llama-3.3-70B-Instruct) are listed

### Requirement: Open WebUI is accessible via Traefik with TLS
Open WebUI SHALL be reachable via a Traefik-managed HTTPS route. It SHALL NOT be directly port-mapped to `0.0.0.0` on the host.

#### Scenario: HTTPS access via Traefik
- **WHEN** a browser navigates to the configured Open WebUI hostname over HTTPS
- **THEN** the Open WebUI login page loads with a valid TLS certificate

#### Scenario: Port not exposed to host
- **WHEN** `docker compose ps` is inspected
- **THEN** port 3000 is not mapped to the host interface

### Requirement: Open WebUI data persists across container restarts
User accounts, chat history, and settings SHALL be stored in a named Docker volume so they survive container rebuilds and image upgrades.

#### Scenario: Chat history survives container recreation
- **WHEN** the Open WebUI container is removed and recreated
- **THEN** previously stored chat sessions and user accounts remain accessible

#### Scenario: Named volume is defined
- **WHEN** the Compose file is inspected
- **THEN** Open WebUI mounts a named Docker volume for its data directory

### Requirement: Healthcheck is defined
The Open WebUI service SHALL define a Docker healthcheck polling its root path.

#### Scenario: Container reports healthy
- **WHEN** `docker inspect open-webui` is run after startup
- **THEN** health status is `healthy`

### Requirement: Service restarts automatically
The Open WebUI service SHALL have `restart: unless-stopped`.

#### Scenario: Service recovers from restart
- **WHEN** the Open WebUI container exits unexpectedly
- **THEN** Docker restarts it automatically

### Requirement: Open WebUI image tag is pinned
The Open WebUI image SHALL use a specific version tag, never `latest`.

#### Scenario: Image tag is pinned in Compose file
- **WHEN** the Compose file is inspected
- **THEN** the Open WebUI image reference includes an explicit version tag (e.g., `v0.6.0`)
