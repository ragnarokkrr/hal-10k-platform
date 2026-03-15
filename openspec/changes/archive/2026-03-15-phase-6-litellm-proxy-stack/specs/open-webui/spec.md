## MODIFIED Requirements

### Requirement: Open WebUI does not declare depends_on litellm at the compose level
Open WebUI SHALL NOT declare `depends_on: litellm` in `compose/ai/docker-compose.yml`. The LiteLLM service lives in a separate compose project. Open WebUI SHALL connect to LiteLLM via the shared `ai_internal` external network using `OPENAI_API_BASE_URL=http://litellm:4000/v1`. It SHALL start independently and show a backend error if the proxy stack is not yet running, rather than failing to start.

#### Scenario: Open WebUI starts without LiteLLM running
- **WHEN** `docker compose -f compose/ai/docker-compose.yml up -d` is run with the proxy stack not running
- **THEN** Open WebUI starts successfully and shows a connection error in the UI rather than refusing to start

#### Scenario: Open WebUI connects to LiteLLM once proxy stack is up
- **WHEN** `docker compose -f compose/proxy/docker-compose.yml up -d` is subsequently run
- **THEN** Open WebUI chat becomes functional without restarting Open WebUI

### Requirement: Open WebUI uses ai_internal as an external named network
The `ai_internal` network in `compose/ai/docker-compose.yml` SHALL be declared as `external: true` with `name: ai_internal`. Open WebUI SHALL remain attached to it.

#### Scenario: ai_internal declared external in compose/ai
- **WHEN** the `networks:` section of `compose/ai/docker-compose.yml` is inspected
- **THEN** `ai_internal` has `external: true`
