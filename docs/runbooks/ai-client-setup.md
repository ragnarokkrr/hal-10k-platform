# Runbook: AI Client Setup — Claude Code, OpenCode & Cline

Configure Claude Code and Cline to use local models via the LiteLLM proxy.

**LiteLLM base URL**: `https://litellm.hal.local`
**Auth**: Bearer token — value of `LITELLM_MASTER_KEY` from `/srv/platform/secrets/ai.yaml`

---

## Pre-condition: Trust the HAL-10k TLS Certificate

The platform uses a self-signed wildcard cert for `*.hal.local`. Add it to your
laptop's trust store before proceeding — clients that use the system CA bundle
(including Claude Code and Cline) will fail to connect otherwise.

```bash
# Copy the cert from HAL-10k
scp hal-10k:/srv/platform/secrets/hal-local.crt ~/hal-local.crt

# Install into the system trust store
sudo cp ~/hal-local.crt /usr/local/share/ca-certificates/hal-local.crt
sudo update-ca-certificates
```

Verify the endpoint is reachable:

```bash
curl -sf \
  -H "Authorization: Bearer $(grep LITELLM_MASTER_KEY /srv/platform/secrets/ai.yaml | cut -d' ' -f2)" \
  https://litellm.hal.local/models | python3 -m json.tool
```

---

## Get Your API Key

```bash
grep LITELLM_MASTER_KEY /srv/platform/secrets/ai.yaml | cut -d' ' -f2
```

Keep this key; you'll need it in every client.

---

## Claude Code

Claude Code supports a custom OpenAI-compatible endpoint via environment variables or
`claude config`.

### Option A — Environment variables (per-session)

```bash
export ANTHROPIC_BASE_URL=https://litellm.hal.local
export ANTHROPIC_API_KEY=<LITELLM_MASTER_KEY>

# Override the default model for this session
claude --model qwen2.5-coder:32b
```

### Option B — `claude config` (persistent)

```bash
# Set the base URL to the LiteLLM proxy
claude config set -g apiBaseUrl https://litellm.hal.local

# Set the API key
claude config set -g apiKey <LITELLM_MASTER_KEY>
```

> To revert to Anthropic cloud, unset or remove these config values:
> ```bash
> claude config unset -g apiBaseUrl
> claude config unset -g apiKey
> ```

### Verify

```bash
claude --model qwen2.5-coder:32b "What model are you?"
```

### Agentic Tool Use — Use `-tools` Model Aliases

Claude Code's agentic capabilities (file edits, bash execution, codebase exploration)
require structured function/tool calls. Use the `-tools` suffix aliases to route to the
llama.cpp backends, which support function calling via Jinja2 chat templates:

```bash
# Start the llama.cpp backends first (if not already running)
docker compose -f /srv/platform/repos/hal-10k-platform/compose/ai-tools/docker-compose.yml \
  up -d llama-cpp-qwen32b

# Use the -tools alias for agentic sessions
claude --model qwen2.5-coder:32b-tools
```

| Model alias | Backend | Tool calling |
|-------------|---------|-------------|
| `qwen2.5-coder:32b` | Ollama | No |
| `qwen2.5-coder:32b-tools` | llama.cpp | **Yes** |
| `deepseek-r1:32b` | Ollama | No |
| `deepseek-r1:32b-tools` | llama.cpp | **Yes** |
| `llama3.3:70b` | Ollama | No |
| `llama3.3:70b-tools` | llama.cpp | **Yes** |

> **Note:** The llama.cpp backends in `compose/ai-tools/` are not auto-started.
> Start them on demand before agentic sessions and stop them when done to free VRAM.
> See [VRAM budget notes](gguf-model-setup.md#vram-budget) for multi-model constraints.

For chat-only use, the non-`-tools` aliases via Ollama are preferred (lighter weight).

---

## OpenCode

OpenCode is an open-source terminal coding agent that uses OpenAI function calling
format natively. It can connect to local models via LiteLLM for chat and code generation.

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/opencode-ai/opencode/refs/heads/main/install | bash
```

### Configure

Create `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "hal": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "HAL-10k",
      "options": {
        "baseURL": "https://litellm.hal.local/v1",
        "apiKey": "{env:LITELLM_API_KEY}"
      },
      "models": {
        "qwen2.5-coder:32b":       { "name": "Qwen2.5 Coder 32B (chat)"  },
        "qwen2.5-coder:32b-tools": { "name": "Qwen2.5 Coder 32B (tools)" },
        "deepseek-r1:32b":         { "name": "DeepSeek R1 32B (chat)"    },
        "deepseek-r1:32b-tools":   { "name": "DeepSeek R1 32B (tools)"   },
        "llama3.3:70b":            { "name": "Llama 3.3 70B (chat)"      },
        "llama3.3:70b-tools":      { "name": "Llama 3.3 70B (tools)"     }
      }
    }
  }
}
```

### TLS: Trust the HAL-10k Certificate

OpenCode is a Node.js app and **does not use the system CA trust store**. Set
`NODE_EXTRA_CA_CERTS` to avoid "self signed certificate" errors:

```bash
# On HAL-10k
export NODE_EXTRA_CA_CERTS=/srv/platform/secrets/hal-local.crt

# On a remote laptop (after the scp in Pre-conditions above)
export NODE_EXTRA_CA_CERTS=~/hal-local.crt
```

Add to `~/.bashrc` or `~/.zshrc` to make it permanent.

### Launch

```bash
export LITELLM_API_KEY=<LITELLM_MASTER_KEY>
export NODE_EXTRA_CA_CERTS=~/hal-local.crt  # or /srv/platform/secrets/hal-local.crt on HAL-10k
opencode --model hal/qwen2.5-coder:32b
```

### Verify

```bash
opencode --model hal/qwen2.5-coder:32b run "What is 2+2?"
```

### Agentic Tool Use — Use `-tools` Model Aliases

OpenCode's agentic capabilities (file edits, bash execution, codebase exploration)
require structured function/tool calls. Use the `-tools` suffix aliases to route to the
llama.cpp backends, which support function calling via Jinja2 chat templates:

```bash
# Start the llama.cpp backend first (run on HAL-10k)
docker compose -f /srv/platform/repos/hal-10k-platform/compose/ai-tools/docker-compose.yml \
  up -d llama-cpp-qwen32b

# Use the -tools alias for agentic sessions
opencode --model hal/qwen2.5-coder:32b-tools
```

| Model alias | Backend | Tool calling |
|-------------|---------|-------------|
| `qwen2.5-coder:32b` | Ollama | No |
| `qwen2.5-coder:32b-tools` | llama.cpp | **Yes** |
| `deepseek-r1:32b` | Ollama | No |
| `deepseek-r1:32b-tools` | llama.cpp | **Yes** |
| `llama3.3:70b` | Ollama | No |
| `llama3.3:70b-tools` | llama.cpp | **Yes** |

> **Note:** The llama.cpp backends in `compose/ai-tools/` are not auto-started.
> Start them on demand before agentic sessions and stop them when done to free VRAM.
> See [VRAM budget notes](gguf-model-setup.md#vram-budget) for multi-model constraints.
> The 70B model requires stopping the 32B containers first.

---

## Cline (VS Code Extension)

1. Open VS Code Settings → search **Cline**
2. Under **API Provider**, select **OpenAI Compatible**
3. Set:
   - **Base URL**: `https://litellm.hal.local/v1`
   - **API Key**: `<LITELLM_MASTER_KEY>`
   - **Model**: `qwen2.5-coder:32b` (or any model from `litellm.hal.local/models`)
4. Click **Verify** to confirm the connection

---

## Any OpenAI SDK Client

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://litellm.hal.local/v1",
    api_key="<LITELLM_MASTER_KEY>",
)

response = client.chat.completions.create(
    model="qwen2.5-coder:32b",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

---

## List Available Models

```bash
curl -sf \
  -H "Authorization: Bearer $(grep LITELLM_MASTER_KEY /srv/platform/secrets/ai.yaml | cut -d' ' -f2)" \
  https://litellm.hal.local/models | python3 -m json.tool
```

