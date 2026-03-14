# Runbook: AI Inference Stack

**Stack**: `compose/ai/`
**Services**: Ollama · LiteLLM · Open WebUI
**Related ADR**: [ADR-0006](../decisions/adr/ADR-0006-llm-serving-ollama-litellm.md)

---

## Prerequisites

- Traefik core stack is running (`docker compose -f compose/core/docker-compose.yml ps`)
- `traefik` external Docker network exists
- `/srv/platform/models/` directory exists (model weights location)
- SOPS age key is available: `echo $SOPS_AGE_KEY_FILE`
- `/etc/hosts` contains entries for the AI service hostnames (no local DNS server):
  ```
  127.0.0.1  litellm.hal.local
  127.0.0.1  openwebui.hal.local
  ```
  Add if missing: `echo "127.0.0.1  litellm.hal.local openwebui.hal.local" | sudo tee -a /etc/hosts`

---

## 1. First-Time Setup

### 1.1 Prepare secrets

```bash
# Decrypt placeholder secrets
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
./scripts/secrets-decrypt.sh ai

# Verify decrypted file (keys should be non-placeholder values)
cat /srv/platform/secrets/ai.yaml
```

> The `secrets/ai.enc.yaml` in the repo ships with pre-generated secure values.
> Re-generate only if you suspect compromise (see re-encryption steps below).

### 1.2 Set image tags

```bash
cd compose/ai
cp .env.example .env
# Edit .env — confirm OLLAMA_IMAGE, LITELLM_IMAGE, OPEN_WEBUI_IMAGE tags
# Check for latest ROCm Ollama: https://hub.docker.com/r/ollama/ollama/tags
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
docker compose -f compose/ai/docker-compose.yml up -d
```

### Verify all containers are healthy

```bash
docker compose -f compose/ai/docker-compose.yml ps
# Expected: ollama, litellm, open-webui — all Status: running (healthy)
```

Allow 60–90 seconds for LiteLLM to start (it initialises after Ollama is healthy).

---

## 3. GPU Verification

```bash
# Check Ollama logs for ROCm device detection
docker logs ollama 2>&1 | grep -iE "rocm|gpu|amdgpu|gfx"

# Confirm GPU is visible inside the container
docker exec ollama sh -c "ls /dev/dri/ && ls /dev/kfd"

# Quick inference smoke test (pulls a small model if not present)
docker exec -it ollama ollama run qwen2.5-coder:7b "Hello, what model are you?"
```

If you see `HSA_STATUS_ERROR_INVALID_ISA` or similar:
```bash
# Check the GFX version override in docker-compose.yml
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
MASTER_KEY=$(grep LITELLM_MASTER_KEY /srv/platform/secrets/ai.yaml | cut -d' ' -f2)

# List available models
curl -sf -H "Authorization: Bearer ${MASTER_KEY}" \
  https://litellm.hal.local/models | python3 -m json.tool

# Test completion (replace model name as needed)
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
# Stop and remove containers (model weights at /srv/platform/models/ are unaffected)
docker compose -f compose/ai/docker-compose.yml down

# To also remove the Open WebUI data volume (destroys chat history — irreversible):
docker compose -f compose/ai/docker-compose.yml down -v
```

---

## 7. Restart a Single Service

```bash
# Restart Ollama only
docker compose -f compose/ai/docker-compose.yml restart ollama

# Restart LiteLLM (e.g. after updating litellm-config.yaml)
docker compose -f compose/ai/docker-compose.yml restart litellm
```

---

## 8. Rotate Secrets

```bash
# Generate new keys
NEW_MASTER=$(openssl rand -hex 32 | sed 's/^/sk-/')
NEW_SECRET=$(openssl rand -hex 32)
NEW_WEBUI=$(openssl rand -hex 32)

# Write new plaintext file
cat > /srv/platform/secrets/ai.yaml << YAML
LITELLM_MASTER_KEY: ${NEW_MASTER}
LITELLM_SECRET_KEY: ${NEW_SECRET}
OPENAI_API_KEY: ${NEW_MASTER}
WEBUI_SECRET_KEY: ${NEW_WEBUI}
YAML

# Re-encrypt and commit
cp /srv/platform/secrets/ai.yaml \
   /srv/platform/repos/hal-10k-platform/secrets/ai.enc.yaml
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops --encrypt --in-place \
  /srv/platform/repos/hal-10k-platform/secrets/ai.enc.yaml
cd /srv/platform/repos/hal-10k-platform
git add secrets/ai.enc.yaml
git commit -m "chore(secrets): rotate ai stack secrets"

# Restart to pick up new keys
docker compose -f compose/ai/docker-compose.yml up -d --force-recreate
```

> Update any API clients (Claude Code, Cline) with the new LITELLM_MASTER_KEY.

---

## 9. Logs

```bash
# All services
docker compose -f compose/ai/docker-compose.yml logs -f

# Individual service
docker logs -f ollama
docker logs -f litellm
docker logs -f open-webui
```
