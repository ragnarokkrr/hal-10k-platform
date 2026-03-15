# Runbook: AI Client Setup — Claude Code & Cline

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
curl -sf https://litellm.hal.local/models | python3 -m json.tool
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

### Known Limitation — Agentic Tool Use

Claude Code's agentic capabilities (file edits, bash execution, codebase exploration)
rely on Anthropic's structured tool use API format. Local models served via Ollama do
not reliably follow this format — they may describe actions in natural language instead
of emitting proper tool calls, so tasks like "create a file" or "run tests" will silently
fail or produce incorrect output.

**Local models are suitable for:** code generation questions, explanations, and chat.
**Local models are NOT suitable for:** any task that requires Claude Code to take actions
(read/write files, run commands, search the codebase, etc.).

For agentic work, revert to Anthropic cloud:

```bash
unset ANTHROPIC_BASE_URL
unset ANTHROPIC_API_KEY
claude  # uses stored Anthropic credentials
```

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
        "qwen2.5-coder:32b": { "name": "Qwen2.5 Coder 32B" },
        "deepseek-r1:32b":   { "name": "DeepSeek R1 32B"   },
        "llama3.3:70b":      { "name": "Llama 3.3 70B"     }
      }
    }
  }
}
```

Export the key before launching:

```bash
export LITELLM_API_KEY=<LITELLM_MASTER_KEY>
```

### Launch

```bash
opencode --model hal/qwen2.5-coder:32b
```

### Verify

```bash
opencode --model hal/qwen2.5-coder:32b run "What model are you?"
```

### Known Limitation — Tool Use Blocked by Ollama

Agentic tasks (file edits, bash execution, codebase exploration) require the model to
make structured function calls. **None of the current Ollama-served models support
function calling** — Ollama rejects tool-enabled requests for all three models:

| Model | Tools supported |
|-------|----------------|
| qwen2.5-coder:32b | No |
| deepseek-r1:32b | No |
| llama3.3:70b | No |

This is an Ollama-level constraint, not a client issue. Both OpenCode and Claude Code
are affected equally. Until Ollama adds tool/function calling support for these models,
local models are limited to **chat and code generation only**.

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

