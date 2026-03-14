# Runbook: AI Client Setup — Claude Code & Cline

Configure Claude Code and Cline to use local models via the LiteLLM proxy.

**LiteLLM base URL**: `https://litellm.hal.local`
**Auth**: Bearer token — value of `LITELLM_MASTER_KEY` from `/srv/platform/secrets/ai.yaml`

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

---

## TLS Certificate Note

The platform uses a self-signed wildcard cert for `*.hal.local`. Clients may warn about
or reject the certificate.

- **curl**: use `-k` / `--insecure` to skip verification (testing only), or add the cert
  to your trust store:
  ```bash
  sudo cp /srv/platform/secrets/hal-local.crt /usr/local/share/ca-certificates/hal-local.crt
  sudo update-ca-certificates
  ```
- **Python**: set `REQUESTS_CA_BUNDLE` or `SSL_CERT_FILE` to the cert path, or pass
  `verify=False` to the OpenAI client (testing only).
- **Claude Code / Cline**: import `hal-local.crt` into your OS trust store; both tools
  use the system CA bundle.
