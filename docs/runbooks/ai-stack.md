# Runbook: AI Inference Stack

**Stacks**: `compose/ai/` · `compose/proxy/`
**Services**: Ollama · Open WebUI (`compose/ai/`) — LiteLLM (`compose/proxy/`)
**Related ADRs**: [ADR-0006](../decisions/adr/ADR-0006-llm-serving-ollama-litellm.md) · [ADR-0011](../decisions/adr/ADR-0011-llama-cpp-function-calling-stack.md)

---

## Stack Topology

```
Clients (Claude Code, OpenCode, browser)
         ↓ HTTPS via Traefik
  compose/proxy/   — LiteLLM API gateway (litellm.hal.local)
         ↓ ai_internal network
  compose/ai/      — Ollama (inference) · Open WebUI (openwebui.hal.local)
```

**Startup order**: `compose/core/` → `compose/ai/` → `compose/proxy/`
**Teardown order**: `compose/proxy/` → `compose/ai/` → `compose/core/`

The `ai_internal` Docker network is owned by `compose/ai/` (created with `name: ai_internal`).
It must exist before `compose/proxy/` starts.

---

## Prerequisites

- Traefik core stack is running: `docker compose -f compose/core/docker-compose.yml ps`
- `traefik` external Docker network exists
- `/srv/platform/models/` directory exists (model weights location)
- SOPS age key is available: `echo $SOPS_AGE_KEY_FILE`
- `/etc/hosts` contains entries for the AI service hostnames:
  ```
  127.0.0.1  litellm.hal.local
  127.0.0.1  openwebui.hal.local
  ```
  Add if missing: `echo "127.0.0.1  litellm.hal.local openwebui.hal.local" | sudo tee -a /etc/hosts`

---

## 1. First-Time Setup

### 1.1 Prepare secrets

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Inference stack secrets (Open WebUI session key, LiteLLM master key for Open WebUI)
./scripts/secrets-decrypt.sh ai

# Proxy stack secrets (LiteLLM master key, LiteLLM secret key)
./scripts/secrets-decrypt.sh proxy

# Verify keys are present
grep -E "^[A-Z_]+:" /srv/platform/secrets/ai.yaml
grep -E "^[A-Z_]+:" /srv/platform/secrets/proxy.yaml
```

> Both `secrets/ai.enc.yaml` and `secrets/proxy.enc.yaml` ship with pre-generated secure
> values. Re-generate only if you suspect compromise.

### 1.2 Set image tags

```bash
# Inference stack
cd compose/ai && cp .env.example .env
# Edit .env — confirm OLLAMA_IMAGE, OPEN_WEBUI_IMAGE tags

# Proxy stack
cd compose/proxy && cp .env.example .env
# Edit .env — confirm LITELLM_IMAGE tag
```

### 1.3 Ensure models directory exists

```bash
ls -lh /srv/platform/models/   # should exist; create if missing:
# mkdir -p /srv/platform/models
```

---

## 2. Bring Up

```bash
cd /srv/platform/repos/hal-10k-platform

# Step 1: inference stack (creates ai_internal network)
docker compose -f compose/ai/docker-compose.yml up -d

# Step 2: proxy stack (attaches to ai_internal)
docker compose -f compose/proxy/docker-compose.yml up -d
```

### Verify all containers are healthy

```bash
docker compose -f compose/ai/docker-compose.yml ps
# Expected: ollama, open-webui — all Status: running (healthy)

docker compose -f compose/proxy/docker-compose.yml ps
# Expected: litellm — Status: running (healthy)
```

Allow 60–90 seconds for LiteLLM to reach healthy status.

---

## 3. GPU Verification

```bash
# Check Ollama logs for ROCm device detection
docker logs ollama 2>&1 | grep -iE "rocm|gpu|amdgpu|gfx"

# Confirm GPU is visible inside the container
docker exec ollama sh -c "ls /dev/dri/ && ls /dev/kfd"

# Quick inference smoke test
docker exec -it ollama ollama run qwen2.5-coder:7b "Hello, what model are you?"
```

If you see `HSA_STATUS_ERROR_INVALID_ISA` or similar:
```bash
# Check the GFX version override in compose/ai/docker-compose.yml
# For RDNA 3.5 Strix Point: HSA_OVERRIDE_GFX_VERSION=11.0.2
docker inspect ollama | grep -A2 HSA_OVERRIDE
```

---

## 4. Pull Initial Model Roster

These pulls take significant time and disk space. Run them after GPU verification.

```bash
# Qwen2.5-Coder 32B — primary coding model (~20 GB)
docker exec ollama ollama pull qwen2.5-coder:32b

# DeepSeek-R1 32B — reasoning model (~20 GB)
docker exec ollama ollama pull deepseek-r1:32b

# Llama 3.3 70B Instruct — general purpose (~43 GB)
docker exec ollama ollama pull llama3.3:70b

# Verify all three are present
docker exec ollama ollama list
```

Disk usage estimate: ~85 GB total. Check partition headroom first:
```bash
df -h /srv/platform
```

---

## 5. Smoke Tests

### LiteLLM API

```bash
MASTER_KEY=$(grep LITELLM_MASTER_KEY /srv/platform/secrets/proxy.yaml | cut -d' ' -f2)

# List available models
curl -sf -H "Authorization: Bearer ${MASTER_KEY}" \
  https://litellm.hal.local/models | python3 -m json.tool

# Test completion
curl -sf -X POST https://litellm.hal.local/v1/chat/completions \
  -H "Authorization: Bearer ${MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen2.5-coder:32b","messages":[{"role":"user","content":"Say hello"}]}' \
  | python3 -m json.tool
```

### Open WebUI

Open `https://openwebui.hal.local` in a browser. You should see the login page with a
valid (self-signed) TLS certificate from `*.hal.local`.

---

## 6. Tear Down

```bash
# Tear down in reverse startup order

# Step 1: proxy stack
docker compose -f compose/proxy/docker-compose.yml down

# Step 2: inference stack (removes ai_internal network)
# Model weights at /srv/platform/models/ are unaffected
docker compose -f compose/ai/docker-compose.yml down

# To also remove the Open WebUI data volume (destroys chat history — irreversible):
docker compose -f compose/ai/docker-compose.yml down -v
```

> Do not tear down `compose/ai/` before `compose/proxy/` — the proxy depends on the
> `ai_internal` network owned by the ai stack.

---

## 7. Restart a Single Service

```bash
# Restart Ollama only
docker compose -f compose/ai/docker-compose.yml restart ollama

# Restart Open WebUI only
docker compose -f compose/ai/docker-compose.yml restart open-webui

# Restart LiteLLM (e.g. after updating compose/proxy/litellm-config.yaml)
docker compose -f compose/proxy/docker-compose.yml restart litellm
```

Restarting `compose/proxy/` does not affect Ollama or Open WebUI.

---

## 8. Rotate Secrets

### Proxy secrets (LiteLLM keys)

```bash
NEW_MASTER=$(openssl rand -hex 32 | sed 's/^/sk-/')
NEW_SECRET=$(openssl rand -hex 32)

cat > /srv/platform/secrets/proxy.yaml << YAML
LITELLM_MASTER_KEY: ${NEW_MASTER}
LITELLM_SECRET_KEY: ${NEW_SECRET}
YAML

cp /srv/platform/secrets/proxy.yaml \
   /srv/platform/repos/hal-10k-platform/secrets/proxy.enc.yaml
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops --encrypt --in-place \
  /srv/platform/repos/hal-10k-platform/secrets/proxy.enc.yaml
cd /srv/platform/repos/hal-10k-platform
git add secrets/proxy.enc.yaml
git commit -m "chore(secrets): rotate proxy stack secrets"

docker compose -f compose/proxy/docker-compose.yml up -d --force-recreate
```

### AI stack secrets (Open WebUI keys)

```bash
NEW_WEBUI=$(openssl rand -hex 32)
NEW_MASTER=$(grep LITELLM_MASTER_KEY /srv/platform/secrets/proxy.yaml | cut -d' ' -f2)

cat > /srv/platform/secrets/ai.yaml << YAML
LITELLM_MASTER_KEY: ${NEW_MASTER}
LITELLM_SECRET_KEY: $(grep LITELLM_SECRET_KEY /srv/platform/secrets/proxy.yaml | cut -d' ' -f2)
OPENAI_API_KEY: ${NEW_MASTER}
WEBUI_SECRET_KEY: ${NEW_WEBUI}
YAML

cp /srv/platform/secrets/ai.yaml \
   /srv/platform/repos/hal-10k-platform/secrets/ai.enc.yaml
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops --encrypt --in-place \
  /srv/platform/repos/hal-10k-platform/secrets/ai.enc.yaml
cd /srv/platform/repos/hal-10k-platform
git add secrets/ai.enc.yaml
git commit -m "chore(secrets): rotate ai stack secrets"

docker compose -f compose/ai/docker-compose.yml up -d --force-recreate
```

> Update any API clients (Claude Code, Cline) with the new `LITELLM_MASTER_KEY`.

---

## 9. Logs

```bash
# Inference stack
docker compose -f compose/ai/docker-compose.yml logs -f

# Proxy stack
docker compose -f compose/proxy/docker-compose.yml logs -f

# Individual containers
docker logs -f ollama
docker logs -f litellm
docker logs -f open-webui
```
