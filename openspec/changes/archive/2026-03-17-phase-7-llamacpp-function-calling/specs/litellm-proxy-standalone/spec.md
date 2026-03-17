## ADDED Requirements

### Requirement: LiteLLM config routes tool-capable model aliases to per-model llama.cpp containers
The `litellm-config.yaml` in `compose/proxy/` SHALL include `-tools` suffixed model aliases that route to dedicated llama.cpp containers on the `ai_internal` network: `qwen2.5-coder:32b-tools` → `http://llama-cpp-qwen32b:8080/v1`, `deepseek-r1:32b-tools` → `http://llama-cpp-deepseek32b:8080/v1`, `llama3.3:70b-tools` → `http://llama-cpp-llama70b:8080/v1`.

#### Scenario: Tool alias routes to correct llama.cpp container
- **WHEN** a chat completion request is sent to `https://litellm.hal.local/v1/chat/completions` with model `qwen2.5-coder:32b-tools` and a `tools` array
- **THEN** the request is forwarded to the `llama-cpp-qwen32b` container on the ai_internal network and a response with `tool_calls` is returned

#### Scenario: Non-tools alias still routes to Ollama
- **WHEN** a chat completion request is sent with model `qwen2.5-coder:32b` (no `-tools` suffix)
- **THEN** the request is forwarded to Ollama, not llama.cpp

#### Scenario: Unavailable backend returns 502 gracefully
- **WHEN** a chat completion request is sent with model `llama3.3:70b-tools` but `llama-cpp-llama70b` is not running
- **THEN** LiteLLM returns HTTP 502 and recovers automatically when the backend starts

## MODIFIED Requirements

### Requirement: LiteLLM config routes to Ollama via ai_internal
The `litellm-config.yaml` in `compose/proxy/` SHALL set `api_base` to `http://ollama:11434/v1` for all Ollama-backed models and `http://llama-cpp-<name>:8080/v1` for all `-tools` suffixed model aliases (each pointing to a dedicated container). All backends are reachable via the shared `ai_internal` network.

#### Scenario: Model completion routes to Ollama
- **WHEN** a chat completion request is sent to `https://litellm.hal.local/v1/chat/completions` with a chat model name (no `-tools` suffix)
- **THEN** the request is forwarded to Ollama on the ai_internal network and a valid response is returned

#### Scenario: Tool model completion routes to llama.cpp
- **WHEN** a chat completion request is sent to `https://litellm.hal.local/v1/chat/completions` with a `-tools` model alias
- **THEN** the request is forwarded to llama-cpp on the ai_internal network and a valid response with `tool_calls` is returned
